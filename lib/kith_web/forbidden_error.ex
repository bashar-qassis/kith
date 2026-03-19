defmodule KithWeb.ForbiddenError do
  @moduledoc "Raised when a user attempts an action they are not authorized for."

  defexception message: "forbidden", plug_status: 403
end
