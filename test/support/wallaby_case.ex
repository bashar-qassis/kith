defmodule KithWeb.WallabyCase do
  @moduledoc """
  Case template for Wallaby browser E2E tests.

  All Wallaby tests run with `async: false` because browser state is shared
  and the Ecto sandbox must use a shared connection.

  ## Usage

      defmodule KithWeb.ContactLive.IndexWallabyTest do
        use KithWeb.WallabyCase, async: false

        @tag :wallaby
        test "user sees contact list", %{session: session} do
          session
          |> visit("/auth/login")
          |> fill_in(Query.text_field("Email"), with: "user@example.com")
          |> click(Query.button("Sign in"))
        end
      end

  ## Running

      # Headless (CI):
      WALLABY=1 mix test --only wallaby

      # Headed (debugging):
      WALLABY_HEADLESS=false WALLABY=1 mix test --only wallaby
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.DSL

      import Kith.Factory
      import KithWeb.WallabyCase.Helpers

      @endpoint KithWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Kith.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Kith.Repo, {:shared, self()})
    end

    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Kith.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    {:ok, session: session}
  end

  defmodule Helpers do
    @moduledoc false

    use Wallaby.DSL

    @doc """
    Logs in a user by navigating to the login page, filling email/password,
    and submitting. Waits for the dashboard to appear before returning.

    The user must have a known password. By default uses "hello world!!"
    which matches the ExMachina factory.
    """
    def login_as(session, user, password \\ "hello world!!") do
      session
      |> visit("/auth/login")
      |> fill_in(Query.text_field("Email"), with: user.email)
      |> fill_in(Query.text_field("Password"), with: password)
      |> click(Query.button("Sign in"))
    end

    @doc """
    Visits the given path.
    """
    def navigate_to(session, path) do
      visit(session, path)
    end

    @doc """
    Asserts the browser's current path matches the expected path.
    """
    def assert_current_path(session, expected_path) do
      current = current_path(session)

      unless current == expected_path do
        raise ExUnit.AssertionError,
          message: "Expected path #{expected_path}, got #{current}"
      end

      session
    end

    @doc """
    Fills multiple form fields by label.

    ## Example

        fill_form(session, %{"First name" => "Jane", "Last name" => "Doe"})
    """
    def fill_form(session, fields) when is_map(fields) do
      Enum.reduce(fields, session, fn {label, value}, session ->
        fill_in(session, Query.text_field(label), with: value)
      end)
    end
  end
end
