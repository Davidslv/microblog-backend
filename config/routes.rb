Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Root path
  root "posts#index"

  # Posts
  resources :posts, only: [:index, :show, :create]

  # Users
  resources :users, only: [:show, :edit, :update, :destroy]

  # Following
  post '/follow/:user_id', to: 'follows#create', as: 'follow'
  delete '/follow/:user_id', to: 'follows#destroy'

  # Temporary dev route - remove before production!
  get '/dev/login/:user_id', to: 'application#dev_login', as: 'dev_login'

  # Monitoring endpoints (development only)
  if Rails.env.development?
    get '/puma/stats' => proc { |env|
      require 'json'
      stats = Puma.stats
      [200, { 'Content-Type' => 'application/json' }, [stats.to_json]]
    }

    get '/health' => proc { |env|
      require 'json'
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
        status: 'ok',
        timestamp: Time.current.iso8601,
        database: {
          connected: ActiveRecord::Base.connection.active?,
          database_name: database_name,
          adapter: adapter_name
        }
      }
      [200, { 'Content-Type' => 'application/json' }, [health.to_json]]
    }
  end
end
