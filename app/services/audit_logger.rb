class AuditLogger
  def log_report(post, reporter, metadata: {})
    log(
      action: "report",
      post: post,
      user: reporter,
      metadata: metadata
    )
  end

  def log_redaction(post, reason:, admin: nil, metadata: {})
    log(
      action: "redact",
      post: post,
      user: admin,
      admin: admin,
      metadata: metadata.merge(reason: reason)
    )
  end

  def log_unredaction(post, admin:, metadata: {})
    log(
      action: "unredact",
      post: post,
      user: admin,
      admin: admin,
      metadata: metadata
    )
  end

  def log(action:, post:, user: nil, admin: nil, metadata: {})
    # TODO: Consider making audit logging asynchronous for better performance
    # - Create AuditLogJob to process logs in background
    # - Use Solid Queue for reliable delivery
    # - Keep synchronous for critical actions (redactions, unredactions)
    # - Make async for high-volume actions (reports) if needed
    # - Ensure retry logic and error handling to prevent log loss
    # - See: docs/066_MODERATION_OPTION_B_IMPLEMENTATION_PLAN.md (Background Jobs section)
    ModerationAuditLog.create!(
      action: action,
      post: post,
      user: user,
      admin: admin,
      metadata: metadata
    )
  end
end
