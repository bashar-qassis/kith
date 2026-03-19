defmodule Kith.EmailsTest do
  use Kith.DataCase, async: true

  alias Kith.Emails

  defp test_user do
    %{email: "user@example.com", locale: "en"}
  end

  describe "reminder_notification/2" do
    test "builds email with correct subject and content" do
      email =
        Emails.reminder_notification(test_user(), %{
          contact_name: "Alice Smith",
          reminder_title: "Call her back",
          due_date: ~D[2026-03-20]
        })

      assert email.subject == "Reminder: Alice Smith"
      assert {"user@example.com", "user@example.com"} in email.to
      assert email.html_body =~ "Alice Smith"
      assert email.html_body =~ "Call her back"
      assert email.text_body =~ "Alice Smith"
      assert email.text_body =~ "Call her back"
      refute is_nil(email.html_body)
      refute is_nil(email.text_body)
    end
  end

  describe "invitation/2" do
    test "builds invitation email" do
      email =
        Emails.invitation("invitee@example.com", %{
          account_name: "Team Kith",
          inviter_name: "Bob",
          accept_url: "https://kith.example.com/accept/abc123"
        })

      assert email.subject == "You've been invited to Team Kith"
      assert email.html_body =~ "Bob"
      assert email.html_body =~ "Team Kith"
      assert email.html_body =~ "accept/abc123"
      assert email.text_body =~ "accept/abc123"
    end
  end

  describe "welcome/1" do
    test "builds welcome email" do
      email = Emails.welcome(test_user())

      assert email.subject == "Welcome to Kith"
      assert email.html_body =~ "Welcome to Kith"
      assert email.text_body =~ "Welcome to Kith"
      assert email.html_body =~ "Getting Started"
    end
  end

  describe "email_verification/2" do
    test "builds verification email with link and expiry note" do
      email = Emails.email_verification(test_user(), "https://kith.example.com/verify/token123")

      assert email.subject == "Verify your email"
      assert email.html_body =~ "verify/token123"
      assert email.html_body =~ "24 hours"
      assert email.text_body =~ "verify/token123"
      assert email.text_body =~ "24 hours"
    end
  end

  describe "password_reset/2" do
    test "builds reset email with link, expiry, and security warning" do
      email = Emails.password_reset(test_user(), "https://kith.example.com/reset/token456")

      assert email.subject == "Reset your password"
      assert email.html_body =~ "reset/token456"
      assert email.html_body =~ "1 hour"
      assert email.text_body =~ "reset/token456"
      assert email.text_body =~ "SECURITY WARNING"
    end
  end

  describe "data_export_ready/2" do
    test "builds export ready email with download link" do
      email = Emails.data_export_ready(test_user(), "https://kith.example.com/export/dl/abc")

      assert email.subject == "Your data export is ready"
      assert email.html_body =~ "export/dl/abc"
      assert email.html_body =~ "48 hours"
      assert email.text_body =~ "export/dl/abc"
    end
  end

  describe "HTML email safety" do
    test "all emails use inline styles, no <style> blocks" do
      email = Emails.welcome(test_user())
      refute email.html_body =~ "<style>"
      refute email.html_body =~ "</style>"
    end

    test "HTML escaping prevents XSS in user content" do
      email =
        Emails.reminder_notification(test_user(), %{
          contact_name: "<script>alert('xss')</script>",
          reminder_title: "Normal title",
          due_date: ~D[2026-03-20]
        })

      refute email.html_body =~ "<script>"
      assert email.html_body =~ "&lt;script&gt;"
    end
  end
end
