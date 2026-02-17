Rails.application.routes.draw do
  resources :categories do
    collection do
      get :search
    end
    member do
      get :delete
    end
  end
  resources :neighborhood_associations do
    collection do
      get :search
    end
    member do
      get :delete
    end
  end
  resources :tags do
    collection do
      get :search
    end
    member do
      get :delete
    end
  end
  resources :listings do
    collection do
      get :search
    end
    member do
      get :delete
    end
  end

  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords"
  }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
  get "contact", to: "home#contact"

  namespace :panel do
    root to: "dashboard#index"
    resource :profile, only: [:show, :update], controller: "profile"
    resources :members, only: [ :index, :show, :new, :create, :edit, :update ]
    resources :listings do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :residence_certificates, only: [:index, :show, :new, :create]

    delete "reset_account", to: "account_resets#destroy", as: :reset_account

    delete "onboarding/restart", to: "onboarding#restart", as: :onboarding_restart

    get "onboarding/status", to: "onboarding#status", as: :onboarding_status

    scope :onboarding do
      get "step1", to: "onboarding#step1", as: :onboarding_step1
      patch "step1", to: "onboarding#update_step1"
      get "step2", to: "onboarding#step2", as: :onboarding_step2
      patch "step2", to: "onboarding#update_step2"
      delete "step2/document/:attachment_id", to: "onboarding#delete_document", as: :onboarding_delete_document
      get "step3", to: "onboarding#step3", as: :onboarding_step3
      patch "step3", to: "onboarding#update_step3"
      get "step4", to: "onboarding#step4", as: :onboarding_step4
      post "submit", to: "onboarding#submit", as: :onboarding_submit
    end
  end

  namespace :superadmin do
    root to: "dashboard#index"
    resources :categories do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :neighborhood_associations do
      collection do
        get :search
      end
      member do
        get :delete
        post :impersonate
      end
    end
    resources :countries do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :regions do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :communes do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :tags do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :users do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :onboarding_requests, except: [:new, :create] do
      collection { get :search }
      member { get :delete }
    end
    resources :identity_verification_requests, except: [:new, :create] do
      collection { get :search }
      member { get :delete }
    end
    resources :residence_verification_requests, except: [:new, :create] do
      collection { get :search }
      member { get :delete }
    end
  end

  namespace :admin do
    post "stop_impersonating", to: "impersonations#stop"
    root to: "dashboard#index"
    resources :neighborhood_delegations do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :household_units do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :verifications, only: [ :index, :show ] do
      member do
        patch :approve
        patch :reject
      end
    end
    resources :members do
      collection do
        get :search
      end
      member do
        get :delete
        patch :approve
        patch :reject
      end
    end
    resources :listings do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :board_members do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :residence_certificates do
      collection do
        get :search
      end
      member do
        get :delete
        patch :approve
        patch :reject
        patch :issue
      end
    end
  end
end
