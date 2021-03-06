#mixin for all guardian methods dealing with post permisions
module PostGuardain
  # Can the user act on the post in a particular way.
  #  taken_actions = the list of actions the user has already taken
  def post_can_act?(post, action_key, opts={})

    taken = opts[:taken_actions].try(:keys).to_a
    is_flag = PostActionType.is_flag?(action_key)
    already_taken_this_action = taken.any? && taken.include?(PostActionType.types[action_key])
    already_did_flagging      = taken.any? && (taken & PostActionType.flag_types.values).any?

    if  authenticated? && post
      # we always allow flagging - NOTE: this does not seem true, see specs. (MVH)
      (is_flag && @user.has_trust_level?(:basic) && not(already_did_flagging)) ||

      # not a flagging action, and haven't done it already
      not(is_flag || already_taken_this_action) &&

      # nothing except flagging on archived posts
      not(post.topic.archived?) &&

      # don't like your own stuff
      not(action_key == :like && is_my_own?(post)) &&

      # no voting more than once on single vote topics
      not(action_key == :vote && opts[:voted_in_topic] && post.topic.has_meta_data_boolean?(:single_vote))
    end
  end

  def can_clear_flags?(post)
    is_staff? && post
  end

  # Can we see who acted on a post in a particular way?
  def can_see_post_actors?(topic, post_action_type_id)
    return false unless topic

    type_symbol = PostActionType.types[post_action_type_id]
    return false if type_symbol == :bookmark
    return can_see_flags?(topic) if PostActionType.is_flag?(type_symbol)

    if type_symbol == :vote
      # We can see votes if the topic allows for public voting
      return false if topic.has_meta_data_boolean?(:private_poll)
    end

    true
  end

  def can_see_deleted_posts?
    is_staff?
  end

  def can_delete_all_posts?(user)
    is_staff? && user && !user.admin? && user.created_at >= SiteSetting.delete_user_max_age.days.ago && user.post_count <= SiteSetting.delete_all_posts_max.to_i
  end

  # Creating Method
  def can_create_post?(parent)
    !SpamRule::AutoBlock.block?(@user) && (
    !parent ||
    !parent.category ||
    Category.post_create_allowed(self).where(:id => parent.category.id).count == 1
    )
  end

  # Editing Method
  def can_edit_post?(post)
    is_staff? || (!post.topic.archived? && is_my_own?(post) && !post.user_deleted && !post.deleted_at && !post.edit_time_limit_expired?)
  end

  # Deleting Methods
  def can_delete_post?(post)
    # Can't delete the first post
    return false if post.post_number == 1

    # Can't delete after post_edit_time_limit minutes have passed
    return false if !is_staff? && post.edit_time_limit_expired?

    # Can't delete posts in archived topics unless you are staff
    return false if !is_staff? && post.topic.archived?

    # You can delete your own posts
    return !post.user_deleted? if is_my_own?(post)

    is_staff?
  end

  # Recovery Method
  def can_recover_post?(post)
    is_staff? || (is_my_own?(post) && post.user_deleted && !post.deleted_at)
  end

  def can_delete_post_action?(post_action)
    # You can only undo your own actions
    is_my_own?(post_action) && not(post_action.is_private_message?) &&

    # Make sure they want to delete it within the window
    post_action.created_at > SiteSetting.post_undo_action_window_mins.minutes.ago
  end

  def can_see_post?(post)
    post.present? && (is_staff? || (!post.deleted_at.present? && can_see_topic?(post.topic)))
  end

  def can_see_post_revision?(post_revision)
    post_revision.present? && (is_staff? || can_see_post?(post_revision.post))
  end

  def can_vote?(post, opts={})
    post_can_act?(post,:vote, opts)
  end
end
