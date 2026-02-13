import Config

config :ueberauth,
       Ueberauth,
       providers: [
         keycloak: {Ueberauth.Strategy.Keycloak, [default_scope: "openid email profile"]}
       ]

config :mobilizon, :auth,
  oauth_consumer_strategies: [
    {:keycloak, "Authelia"}
  ]

config :ueberauth, Ueberauth.Strategy.Keycloak.OAuth,
  client_id: "{{ backbone__authelia__oidc_mobilizon_clientid }}",
  client_secret: "{{ backbone__authelia__oidc_mobilizon_clientsecret }}",
  site: "https://auth.{{ main_domain }}",
  authorize_url: "https://auth.{{ main_domain }}/api/oidc/authorization",
  token_url: "https://auth.{{ main_domain }}/api/oidc/token",
  userinfo_url: "https://auth.{{ main_domain }}/api/oidc/userinfo",
  token_method: :post

config :mobilizon, Mobilizon.Service.Geospatial.Photon,
  endpoint: "http://photon"
