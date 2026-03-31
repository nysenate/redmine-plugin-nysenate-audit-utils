Rails.application.routes.draw do
  # Reporting routes
  resources :projects do
    resources :audit_reports, only: [:index] do
      collection do
        get :daily
        get :weekly
        get :monthly
        get :export
      end
    end
  end

  # User search/autofill routes
  resources :user_search, only: [] do
    collection do
      get :search
      get :field_mappings
    end
  end

  # Settings management routes
  resources :audit_utils_settings, only: [] do
    collection do
      post :autoconfigure_all
      post :autoconfigure_field
      get :configuration_status
      delete :delete_dangling_mapping
      delete :delete_all_dangling_mappings
    end
  end

  # Project-scoped user management routes
  resources :projects do
    resources :tracked_users
  end

  # Packet creation routes
  resources :issues do
    member do
      post :create_packet, to: 'packet_creation#create'
    end
  end

  post 'issues/create_multi_packet', to: 'packet_creation#create_multi_packet'
end
