Rails.application.routes.draw do
  resources :issues do
    member do
      post :create_packet, to: 'packet_creation#create'
    end
  end
end