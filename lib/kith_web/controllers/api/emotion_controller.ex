defmodule KithWeb.API.EmotionController do
  use KithWeb, :controller

  alias Kith.{Contacts, Policy}
  alias Kith.Contacts.Emotion

  import Ecto.Query

  action_fallback KithWeb.API.FallbackController

  def index(conn, _params) do
    account_id = conn.assigns.current_scope.account.id

    emotions =
      Emotion
      |> where([e], is_nil(e.account_id) or e.account_id == ^account_id)
      |> order_by([e], asc: e.position)
      |> Kith.Repo.all()

    json(conn, %{data: Enum.map(emotions, &emotion_json/1)})
  end

  def create(conn, %{"emotion" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :manage, :account) do
      true ->
        case Contacts.create_emotion(account_id, attrs) do
          {:ok, emotion} -> conn |> put_status(201) |> json(%{data: emotion_json(emotion)})
          {:error, cs} -> {:error, cs}
        end

      false ->
        {:error, :forbidden}
    end
  end

  def update(conn, %{"id" => id, "emotion" => attrs}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :manage, :account) do
      true ->
        emotion = Contacts.get_emotion!(account_id, String.to_integer(id))

        case Contacts.update_emotion(emotion, attrs) do
          {:ok, updated} -> json(conn, %{data: emotion_json(updated)})
          {:error, cs} -> {:error, cs}
        end

      false ->
        {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    user = scope.user
    account_id = scope.account.id

    case Policy.can?(user, :manage, :account) do
      true ->
        emotion = Contacts.get_emotion!(account_id, String.to_integer(id))

        case Contacts.delete_emotion(emotion) do
          {:ok, _} -> send_resp(conn, 204, "")
          {:error, cs} -> {:error, cs}
        end

      false ->
        {:error, :forbidden}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp emotion_json(%Emotion{} = e) do
    %{
      id: e.id,
      name: e.name,
      position: e.position,
      is_custom: not is_nil(e.account_id)
    }
  end
end
