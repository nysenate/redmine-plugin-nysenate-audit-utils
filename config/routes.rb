Rails.application.routes.draw do
  resources :issues do
    member do
      post :create_packet, to: 'packet_creation#create'
    end
  end
  
  post 'issues/create_multi_packet', to: 'packet_creation#create_multi_packet'
end