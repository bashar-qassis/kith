defmodule KithWeb.ErrorHTMLTest do
  use KithWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(KithWeb.ErrorHTML, "404", "html", []) =~ "Page not found"
  end

  test "renders 500.html" do
    assert render_to_string(KithWeb.ErrorHTML, "500", "html", []) =~ "Something went wrong"
  end
end
