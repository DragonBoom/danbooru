module UsersHelper
  def unread_dmail_indicator(user)
    "(#{user.unread_dmail_count})" if user.unread_dmail_count > 0
  end

  def has_unread_dmails?(user)
    user.unread_dmail_count > 0 && (cookies[:hide_dmail_notice].to_i < latest_unread_dmail(user).id)
  end

  def latest_unread_dmail(user)
    user.dmails.active.unread.first
  end

  def email_sig(user)
    verifier = ActiveSupport::MessageVerifier.new(Danbooru.config.email_key, serializer: JSON, digest: "SHA256")
    verifier.generate(user.id.to_s)
  end
end
