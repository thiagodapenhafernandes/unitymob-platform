class ApiDocumentationController < ActionController::Base
  def show
    render layout: false
  end

  def openapi
    spec = YAML.safe_load_file(Rails.root.join("docs/openapi.yaml"))
    spec["servers"] = [{ "url" => request.base_url, "description" => "Ambiente atual" }]
    send_data YAML.dump(spec), type: "application/yaml", filename: "unitymob-openapi.yaml", disposition: "inline"
  end
end
