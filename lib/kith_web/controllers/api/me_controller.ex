defmodule KithWeb.API.MeController do
  use KithWeb, :controller

  alias Kith.Accounts

  action_fallback KithWeb.API.FallbackController

  @updatable_fields ~w(locale timezone display_name_format currency temperature_unit default_profile_tab me_contact_id)

  def show(conn, _params) do
    user = conn.assigns.current_scope.user
    json(conn, %{data: user_json(user)})
  end

  def update(conn, %{"user" => attrs}) do
    user = conn.assigns.current_scope.user
    account_id = conn.assigns.current_scope.account.id
    safe_attrs = Map.take(attrs, @updatable_fields)

    # Validate me_contact_id belongs to same account
    safe_attrs =
      case safe_attrs do
        %{"me_contact_id" => cid} when not is_nil(cid) ->
          case Kith.Contacts.get_contact(account_id, cid) do
            nil -> Map.delete(safe_attrs, "me_contact_id")
            _ -> safe_attrs
          end

        _ ->
          safe_attrs
      end

    # TODO: implement Accounts.update_user_settings/2 -- currently proxying to update_user_profile/2
    case Accounts.update_user_profile(user, safe_attrs) do
      {:ok, updated} -> json(conn, %{data: user_json(updated)})
      {:error, cs} -> {:error, cs}
    end
  end

  def update(conn, _params) do
    {:error, :bad_request, "Missing 'user' key in request body."}
  end

  defp user_json(user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      locale: user.locale,
      timezone: user.timezone,
      display_name_format: user.display_name_format,
      currency: user.currency,
      temperature_unit: user.temperature_unit,
      default_profile_tab: user.default_profile_tab,
      me_contact_id: user.me_contact_id,
      totp_enabled: user.totp_enabled,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
