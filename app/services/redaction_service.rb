class RedactionService
  THRESHOLD = 5

  def initialize(content_checker: nil)
    @content_checker = content_checker
  end

  def redact(post, reason: "manual", admin: nil)
    return post if post.redacted? # Already redacted, don't change

    post.update!(
      redacted: true,
      redacted_at: Time.current,
      redaction_reason: reason
    )

    post
  end

  def unredact(post)
    post.update!(
      redacted: false,
      redacted_at: nil,
      redaction_reason: nil
    )

    post
  end

  def check_threshold(post)
    post.report_count >= THRESHOLD
  end

  def auto_redact_if_threshold(post)
    return false if post.redacted? # Already redacted
    return false unless check_threshold(post)

    redact(post, reason: "auto")
    true
  end
end
