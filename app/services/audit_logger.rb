class AuditLogger
  def log_report(post, reporter, metadata: {})
    log(
      action: 'report',
      post: post,
      user: reporter,
      metadata: metadata
    )
  end

  def log_redaction(post, reason:, admin: nil, metadata: {})
    log(
      action: 'redact',
      post: post,
      user: admin,
      admin: admin,
      metadata: metadata.merge(reason: reason)
    )
  end

  def log_unredaction(post, admin:, metadata: {})
    log(
      action: 'unredact',
      post: post,
      user: admin,
      admin: admin,
      metadata: metadata
    )
  end

  def log(action:, post:, user: nil, admin: nil, metadata: {})
    ModerationAuditLog.create!(
      action: action,
      post: post,
      user: user,
      admin: admin,
      metadata: metadata
    )
  end
end

