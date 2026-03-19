defmodule Kith.Emails do
  @moduledoc """
  Email builder functions for all transactional emails.

  Each function returns a `%Swoosh.Email{}` struct with both HTML and
  plain-text versions. Uses inline CSS for email client compatibility.
  """

  import Swoosh.Email

  @from_default {"Kith", "noreply@localhost"}

  # -- Public API --

  @doc "Reminder notification email sent when a reminder fires."
  def reminder_notification(user, %{
        contact_name: contact_name,
        reminder_title: title,
        due_date: due_date
      }) do
    formatted_date = format_date(due_date, user)

    base_email(user)
    |> subject("Reminder: #{contact_name}")
    |> html_body(
      layout("""
      <h2 style="color: #1a1a2e; margin: 0 0 16px;">Reminder</h2>
      <p style="color: #333; font-size: 16px; line-height: 1.5;">
        You have a reminder for <strong>#{html_escape(contact_name)}</strong>:
      </p>
      <div style="background: #f0f4f8; border-left: 4px solid #4a6fa5; padding: 16px; margin: 16px 0; border-radius: 4px;">
        <p style="margin: 0; font-size: 16px; color: #1a1a2e;">#{html_escape(title)}</p>
        <p style="margin: 8px 0 0; font-size: 14px; color: #666;">Due: #{html_escape(formatted_date)}</p>
      </div>
      """)
    )
    |> text_body("""
    Reminder for #{contact_name}

    #{title}
    Due: #{formatted_date}

    #{footer_text()}
    """)
  end

  @doc "Invitation email for inviting a user to an account."
  def invitation(invitee_email, %{
        account_name: account_name,
        inviter_name: inviter_name,
        accept_url: accept_url
      }) do
    new()
    |> to(invitee_email)
    |> from(from_address())
    |> subject("You've been invited to #{account_name}")
    |> html_body(
      layout("""
      <h2 style="color: #1a1a2e; margin: 0 0 16px;">You're Invited!</h2>
      <p style="color: #333; font-size: 16px; line-height: 1.5;">
        <strong>#{html_escape(inviter_name)}</strong> has invited you to join
        <strong>#{html_escape(account_name)}</strong> on Kith.
      </p>
      <div style="text-align: center; margin: 24px 0;">
        <a href="#{html_escape(accept_url)}" style="background: #4a6fa5; color: #fff; padding: 12px 32px; text-decoration: none; border-radius: 6px; font-size: 16px; display: inline-block;">
          Accept Invitation
        </a>
      </div>
      <p style="color: #999; font-size: 13px;">
        If the button doesn't work, copy and paste this URL into your browser:<br>
        <a href="#{html_escape(accept_url)}" style="color: #4a6fa5;">#{html_escape(accept_url)}</a>
      </p>
      """)
    )
    |> text_body("""
    You're Invited!

    #{inviter_name} has invited you to join #{account_name} on Kith.

    Accept the invitation by visiting:
    #{accept_url}

    #{footer_text()}
    """)
  end

  @doc "Welcome email sent after registration."
  def welcome(user) do
    base_email(user)
    |> subject("Welcome to Kith")
    |> html_body(
      layout("""
      <h2 style="color: #1a1a2e; margin: 0 0 16px;">Welcome to Kith!</h2>
      <p style="color: #333; font-size: 16px; line-height: 1.5;">
        Thanks for signing up. Kith helps you stay in touch with the people who matter most.
      </p>
      <h3 style="color: #1a1a2e; margin: 24px 0 12px;">Getting Started</h3>
      <ul style="color: #333; font-size: 15px; line-height: 1.8; padding-left: 20px;">
        <li>Add your first contact from the dashboard</li>
        <li>Set up reminders to stay in touch regularly</li>
        <li>Log calls and activities to build your relationship history</li>
      </ul>
      """)
    )
    |> text_body("""
    Welcome to Kith!

    Thanks for signing up. Kith helps you stay in touch with the people who matter most.

    Getting Started:
    - Add your first contact from the dashboard
    - Set up reminders to stay in touch regularly
    - Log calls and activities to build your relationship history

    #{footer_text()}
    """)
  end

  @doc "Email verification email with confirmation link."
  def email_verification(user, verification_url) do
    base_email(user)
    |> subject("Verify your email")
    |> html_body(
      layout("""
      <h2 style="color: #1a1a2e; margin: 0 0 16px;">Verify Your Email</h2>
      <p style="color: #333; font-size: 16px; line-height: 1.5;">
        Please confirm your email address by clicking the button below.
      </p>
      <div style="text-align: center; margin: 24px 0;">
        <a href="#{html_escape(verification_url)}" style="background: #4a6fa5; color: #fff; padding: 12px 32px; text-decoration: none; border-radius: 6px; font-size: 16px; display: inline-block;">
          Verify Email
        </a>
      </div>
      <p style="color: #999; font-size: 13px;">
        This link expires in 24 hours. If you didn't create an account, you can safely ignore this email.<br><br>
        If the button doesn't work:<br>
        <a href="#{html_escape(verification_url)}" style="color: #4a6fa5;">#{html_escape(verification_url)}</a>
      </p>
      """)
    )
    |> text_body("""
    Verify Your Email

    Please confirm your email address by visiting:
    #{verification_url}

    This link expires in 24 hours. If you didn't create an account, you can safely ignore this email.

    #{footer_text()}
    """)
  end

  @doc "Password reset email with reset link."
  def password_reset(user, reset_url) do
    base_email(user)
    |> subject("Reset your password")
    |> html_body(
      layout("""
      <h2 style="color: #1a1a2e; margin: 0 0 16px;">Reset Your Password</h2>
      <p style="color: #333; font-size: 16px; line-height: 1.5;">
        We received a request to reset your password. Click the button below to choose a new one.
      </p>
      <div style="text-align: center; margin: 24px 0;">
        <a href="#{html_escape(reset_url)}" style="background: #4a6fa5; color: #fff; padding: 12px 32px; text-decoration: none; border-radius: 6px; font-size: 16px; display: inline-block;">
          Reset Password
        </a>
      </div>
      <p style="color: #999; font-size: 13px;">
        This link expires in 1 hour. If you didn't request a password reset, you can safely ignore this email.
        Your password will not change unless you click the link above.<br><br>
        If the button doesn't work:<br>
        <a href="#{html_escape(reset_url)}" style="color: #4a6fa5;">#{html_escape(reset_url)}</a>
      </p>
      <div style="background: #fff3cd; border: 1px solid #ffc107; padding: 12px; border-radius: 4px; margin-top: 16px;">
        <p style="margin: 0; color: #856404; font-size: 13px;">
          &#9888; If you did not request this reset, someone may have entered your email by mistake. No action is needed.
        </p>
      </div>
      """)
    )
    |> text_body("""
    Reset Your Password

    We received a request to reset your password. Visit this link to choose a new one:
    #{reset_url}

    This link expires in 1 hour. If you didn't request a password reset,
    you can safely ignore this email. Your password will not change
    unless you click the link above.

    SECURITY WARNING: If you did not request this reset, someone may have
    entered your email by mistake. No action is needed.

    #{footer_text()}
    """)
  end

  @doc "Data export ready notification with download link."
  def data_export_ready(user, download_url) do
    base_email(user)
    |> subject("Your data export is ready")
    |> html_body(
      layout("""
      <h2 style="color: #1a1a2e; margin: 0 0 16px;">Your Data Export is Ready</h2>
      <p style="color: #333; font-size: 16px; line-height: 1.5;">
        Your data export has been generated and is ready for download.
      </p>
      <div style="text-align: center; margin: 24px 0;">
        <a href="#{html_escape(download_url)}" style="background: #4a6fa5; color: #fff; padding: 12px 32px; text-decoration: none; border-radius: 6px; font-size: 16px; display: inline-block;">
          Download Export
        </a>
      </div>
      <p style="color: #999; font-size: 13px;">
        This download link expires in 48 hours. After that, you'll need to generate a new export.<br><br>
        If the button doesn't work:<br>
        <a href="#{html_escape(download_url)}" style="color: #4a6fa5;">#{html_escape(download_url)}</a>
      </p>
      """)
    )
    |> text_body("""
    Your Data Export is Ready

    Your data export has been generated and is ready for download:
    #{download_url}

    This download link expires in 48 hours. After that, you'll need
    to generate a new export.

    #{footer_text()}
    """)
  end

  # -- Private helpers --

  defp base_email(user) do
    new()
    |> to({user.email, user.email})
    |> from(from_address())
  end

  defp from_address do
    from = Application.get_env(:kith, Kith.Mailer, []) |> Keyword.get(:from)

    case from do
      nil -> @from_default
      addr when is_binary(addr) -> {"Kith", addr}
      tuple -> tuple
    end
  end

  defp layout(content) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
    <body style="margin: 0; padding: 0; background: #f5f5f5; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background: #f5f5f5;">
        <tr><td align="center" style="padding: 32px 16px;">
          <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="background: #fff; border-radius: 8px; overflow: hidden; max-width: 600px;">
            <tr><td style="background: #1a1a2e; padding: 24px; text-align: center;">
              <span style="color: #fff; font-size: 24px; font-weight: 700; letter-spacing: 1px;">Kith</span>
            </td></tr>
            <tr><td style="padding: 32px 24px;">
              #{content}
            </td></tr>
            <tr><td style="background: #f9f9f9; padding: 16px 24px; border-top: 1px solid #eee;">
              <p style="margin: 0; color: #999; font-size: 12px; text-align: center;">
                You received this email because you have a Kith account.
                If you believe this was sent in error, please contact your account administrator.
              </p>
            </td></tr>
          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  defp footer_text do
    "---\nYou received this email because you have a Kith account.\nIf you believe this was sent in error, please contact your account administrator."
  end

  defp format_date(date, user) do
    locale = Map.get(user, :locale, "en") || "en"

    case Kith.Cldr.Date.to_string(date, locale: locale, format: :long) do
      {:ok, formatted} -> formatted
      _ -> to_string(date)
    end
  end

  defp html_escape(nil), do: ""

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp html_escape(other), do: html_escape(to_string(other))
end
