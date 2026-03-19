defmodule Kith.Accounts.UserNotifier do
  import Swoosh.Email

  alias Kith.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Kith", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm a new account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your Kith account", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your Kith password", """

    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver an invitation to join an account.
  """
  def deliver_invitation(email, %{
        account_name: account_name,
        invited_by_name: invited_by_name,
        role: role,
        url: url
      }) do
    deliver(email, "You've been invited to join #{account_name} on Kith", """

    ==============================

    Hi,

    #{invited_by_name} has invited you to join "#{account_name}" on Kith
    as #{a_or_an(role)} #{role}.

    You can accept the invitation by visiting the URL below:

    #{url}

    This invitation expires in 7 days.

    If you weren't expecting this invitation, you can ignore this email.

    ==============================
    """)
  end

  defp a_or_an(word) when word in ["admin", "editor"], do: "an"
  defp a_or_an(_word), do: "a"
end
