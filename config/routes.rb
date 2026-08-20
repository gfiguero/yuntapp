Rails.application.routes.draw do
  # Controllers top-level solo de lectura (BR-007): la gestión (crear/editar/
  # borrar) de juntas, categorías, tags y publicaciones vive exclusivamente en
  # los namespaces superadmin/admin/panel. Aquí solo se expone el browse
  # (index/show/search) para usuarios autenticados, nunca CRUD de escritura.
  resources :categories, only: [:index, :show] do
    collection do
      get :search
    end
  end
  resources :neighborhood_associations, only: [:index, :show] do
    collection do
      get :search
    end
  end
  resources :tags, only: [:index, :show] do
    collection do
      get :search
    end
  end
  resources :listings, only: [:index, :show] do
    collection do
      get :search
    end
  end

  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords"
  }

  # Reactivación auto-servicio de cuentas desactivadas (BR-100, forma A: por correo).
  get "account/reactivate", to: "reactivations#new", as: :new_reactivation
  post "account/reactivate", to: "reactivations#create", as: :reactivations
  get "account/reactivate/:token", to: "reactivations#show", as: :reactivate_account
  patch "account/reactivate/:token", to: "reactivations#update"

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

  # Verificación pública de certificados (UC-007, BR-009).
  # Endpoint sin autenticación: cualquiera puede verificar un certificado por
  # validation_token (UUID) o validation_code (8 chars alfanumérico).
  get "verify", to: "verifications#index", as: :verify
  post "verify", to: "verifications#lookup"
  get "verify/:identifier", to: "verifications#show", as: :verification

  # Guía pública "cómo funciona" (deck explicativo). Sin autenticación.
  get "como-funciona", to: "guide#index", as: :guide

  namespace :panel do
    root to: "dashboard#index"
    resource :profile, only: [:show], controller: "profile"
    resource :neighborhood_association, only: [:show], controller: "neighborhood_association"
    resources :listings do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :residence_certificates, only: [:index, :show, :new, :create] do
      member do
        get :download
      end
    end
    resources :dependents, only: [:index, :new, :create]

    # BR-042: contexto de qué otros núcleos familiares conviven en el domicilio.
    # Solo lectura y sin datos personales de los otros núcleos (BR-041).
    get "household_neighbours", to: "household_neighbours#index", as: :household_neighbours
    resources :payments, only: [:new] do
      collection do
        get :success
        get :failure
        get :pending
      end
    end
    resources :listing_payments, only: [:new] do
      collection do
        get :success
        get :failure
        get :pending
      end
    end
    resources :listing_subscriptions, only: [:new, :create] do
      collection do
        get :success
        delete :cancel
      end
    end

    resource :account_deactivation, only: [:new, :create], controller: "account_deactivations"

    resource :administration_request, only: [:new, :create, :show] do
      delete :cancel, on: :collection
    end

    delete "onboarding/restart", to: "onboarding#restart", as: :onboarding_restart
    delete "onboarding/cancel", to: "onboarding#cancel", as: :onboarding_cancel

    get "onboarding/status", to: "onboarding#status", as: :onboarding_status

    # BR-047: historial de solicitudes con su motivo de rechazo.
    # BR-048/BR-049: duplicar una rechazada o cancelada en una nueva `draft`.
    get "onboarding/history", to: "onboarding_requests#index", as: :onboarding_history
    post "onboarding/history/:id/duplicate", to: "onboarding_requests#duplicate", as: :onboarding_request_duplicate

    scope :onboarding do
      get "step1", to: "onboarding#step1", as: :onboarding_step1
      patch "step1", to: "onboarding#update_step1"
      get "step2", to: "onboarding#step2", as: :onboarding_step2
      patch "step2", to: "onboarding#update_step2"
      delete "step2/document/:attachment_id", to: "onboarding#delete_document", as: :onboarding_delete_document
      get "step3", to: "onboarding#step3", as: :onboarding_step3
      patch "step3", to: "onboarding#update_step3"
      delete "step3/document/:attachment_id", to: "onboarding#delete_residence_document", as: :onboarding_delete_residence_document
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
    resources :neighborhood_associations, except: [:destroy] do
      collection do
        get :search
      end
      member do
        get :deactivate
        patch :confirm_deactivate
        post :impersonate
      end
    end
    resources :administration_requests, only: %i[index show] do
      member do
        patch :approve
        patch :reject
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
    resources :users, except: [:destroy] do
      collection do
        get :search
      end
      member do
        get :block
        patch :confirm_block
        patch :unblock
      end
    end
    resources :onboarding_requests, except: [:new, :create] do
      collection { get :search }
      member { get :delete }
    end
    resources :identity_verification_requests, except: [:new, :create, :destroy] do
      collection { get :search }
    end
    resources :residence_verification_requests, except: [:new, :create, :destroy] do
      collection { get :search }
    end
  end

  namespace :admin do
    post "stop_impersonating", to: "impersonations#stop"
    root to: "dashboard#index"
    resources :neighborhood_delegations, except: [:destroy] do
      collection do
        get :search
      end
    end
    resources :household_units, except: [:destroy] do
      collection do
        get :search
      end
    end
    resources :onboarding_requests, only: [:index, :show] do
      collection do
        get :search
      end
      member do
        scope :review do
          get "step1", to: "onboarding_reviews#step1", as: :review_step1
          get "step2", to: "onboarding_reviews#step2", as: :review_step2
          get "step3", to: "onboarding_reviews#step3", as: :review_step3
          patch "step3", to: "onboarding_reviews#approve_step3"
          patch "reject", to: "onboarding_reviews#reject", as: :review_reject
        end
      end
    end
    resources :verifications, only: [:index, :show] do
      member do
        patch :approve
        patch :reject
      end
    end
    resources :dependent_reviews, only: [:index, :show] do
      member do
        patch :approve
        patch :reject
      end
    end
    resources :members, except: [:destroy] do
      collection do
        get :search
      end
      member do
        get :deactivate
        patch :approve
        patch :reject
        patch :confirm_deactivate
      end
    end
    resources :listings, except: [:new, :create] do
      collection do
        get :search
      end
      member do
        get :delete
      end
    end
    resources :board_members, except: [:destroy] do
      collection do
        get :search
      end
      member do
        get :end_term
        patch :confirm_end_term
      end
    end
    resources :residence_certificates, only: [:index, :show] do
      collection do
        get :search
      end
    end
    resources :certificate_pricings, only: [:index, :new, :create]
    resources :listing_pricings, only: [:index, :new, :create]
  end

  namespace :webhooks do
    post "mercadopago", to: "mercadopago#create"
  end
end
