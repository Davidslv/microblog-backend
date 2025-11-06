Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ============================================================================
  # API ROUTES (New Three-Layer Architecture)
  # ============================================================================
  # These routes run in parallel with the monolith routes below
  # Both use the same database, same models, same business logic
  # API returns JSON, monolith returns HTML
  namespace :api do
    namespace :v1 do
      # Authentication
      post "/login", to: "sessions#create"
      delete "/logout", to: "sessions#destroy"
      get "/me", to: "sessions#show"
      post "/refresh", to: "sessions#refresh"

      # Users
      resources :users, only: [:show, :create, :update, :destroy]
      post "/signup", to: "users#create", as: "api_signup"

      # Posts
      resources :posts, only: [:index, :show, :create] do
        member do
          get :replies
        end
      end

      # Follows
      post "/users/:user_id/follow", to: "follows#create"
      delete "/users/:user_id/follow", to: "follows#destroy"
    end
  end

  # ============================================================================
  # MONOLITH ROUTES (Existing - Keep for Parallel Running)
  # ============================================================================
  # These routes continue to work as before (HTML responses)
  # They share the same database and models with API routes above

  # Root path
  root "posts#index"

  # Posts
  resources :posts, only: [ :index, :show, :create ]

  # Authentication
  get "/login", to: "sessions#new", as: "login"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: "logout"

  # Users (including signup)
  resources :users, only: [ :show, :new, :create, :edit, :update, :destroy ]
  get "/signup", to: "users#new", as: "signup"

  # Following
  post "/follow/:user_id", to: "follows#create", as: "follow"
  delete "/follow/:user_id", to: "follows#destroy"

  # Monitoring endpoints (development only)
  if Rails.env.development?
    # Mission Control – Jobs: UI for monitoring Solid Queue jobs
    # Access at: http://localhost:3000/jobs
    mount MissionControl::Jobs::Engine, at: "/jobs"

    get "/puma/stats" => proc { |env|
      require "json"
      stats = Puma.stats
      [ 200, { "Content-Type" => "application/json" }, [ stats.to_json ] ]
    }

    get "/health" => proc { |env|
      require "json"
      database_name = begin
        ActiveRecord::Base.connection.current_database
      rescue
        nil
      end
      adapter_name = begin
        ActiveRecord::Base.connection.adapter_name
      rescue
        nil
      end
      health = {
        status: "ok",
        timestamp: Time.current.iso8601,
        database: {
          connected: ActiveRecord::Base.connection.active?,
          database_name: database_name,
          adapter: adapter_name
        }
      }
      [ 200, { "Content-Type" => "application/json" }, [ health.to_json ] ]
    }
  end
end
