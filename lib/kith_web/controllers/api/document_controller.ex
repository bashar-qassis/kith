defmodule KithWeb.API.DocumentController do
  use KithWeb, :controller

  alias Kith.{Contacts, Policy, Storage}
  alias Kith.Contacts.Document
  alias Kith.Scope, as: TenantScope
  alias KithWeb.API.Pagination

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  def index(conn, %{"contact_id" => contact_id} = params) do
    account_id = conn.assigns.current_scope.account.id

    case Contacts.get_contact(account_id, contact_id) do
      nil ->
        {:error, :not_found}

      _contact ->
        query =
          Document
          |> TenantScope.scope_to_account(account_id)
          |> where([d], d.contact_id == ^contact_id)

        {docs, meta} = Pagination.paginate(query, params)
        json(conn, Pagination.paginated_response(Enum.map(docs, &doc_json/1), meta))
    end
  end

  def create(conn, %{"contact_id" => contact_id} = params) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :create, :document),
         contact when not is_nil(contact) <- Contacts.get_contact(account_id, contact_id) do
      case params["file"] do
        %Plug.Upload{} = upload ->
          dest = Storage.generate_key(account_id, "documents", upload.filename)

          case Storage.upload(upload.path, dest) do
            {:ok, storage_key} ->
              attrs = %{
                "file_name" => upload.filename,
                "content_type" => upload.content_type,
                "file_size" => File.stat!(upload.path).size,
                "storage_key" => storage_key
              }

              case Contacts.create_document(contact, attrs) do
                {:ok, doc} ->
                  conn
                  |> put_status(201)
                  |> json(%{data: doc_json(doc)})

                {:error, cs} ->
                  {:error, cs}
              end

            {:error, reason} ->
              {:error, :bad_request, "Upload failed: #{inspect(reason)}"}
          end

        nil ->
          {:error, :bad_request, "Missing file upload."}
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    with true <- Policy.can?(user, :delete, :document) do
      case Document |> TenantScope.scope_to_account(account_id) |> Kith.Repo.get(id) do
        nil ->
          {:error, :not_found}

        doc ->
          Kith.Repo.delete(doc)
          send_resp(conn, 204, "")
      end
    else
      false -> {:error, :forbidden}
    end
  end

  defp doc_json(%Document{} = d) do
    %{
      id: d.id,
      contact_id: d.contact_id,
      file_name: d.file_name,
      content_type: d.content_type,
      file_size: d.file_size,
      inserted_at: d.inserted_at
    }
  end
end
