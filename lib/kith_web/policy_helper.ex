defmodule KithWeb.PolicyHelper do
  @moduledoc """
  Convenience wrapper around `Kith.Policy.can?/3` for use in LiveView templates.

  Imported in all LiveView and component modules via KithWeb html_helpers.
  """

  @doc """
  Returns true if the user is authorized to perform the given action on the resource.
  Designed for use in HEEx templates to conditionally render controls.

  ## Examples

      <%= if authorized?(@current_scope.user, :edit, :contact) do %>
        <button>Edit</button>
      <% end %>
  """
  def authorized?(%Kith.Accounts.User{} = user, action, resource) do
    Kith.Policy.can?(user, action, resource)
  end

  def authorized?(nil, _action, _resource), do: false
end
