#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require 'spec_helper'

describe ServicesController do
  let(:omniauth_auth) do
    { 'provider' => 'twitter',
      'uid'      => '2',
      'info'   => { 'nickname' => 'grimmin' },
      'credentials' => { 'token' => 'tokin', 'secret' =>"not_so_much" }}
    end
  let(:user) { alice }

  before do
    sign_in :user, user
    @controller.stub!(:current_user).and_return(user)
  end

  describe '#index' do
    before do
      FactoryGirl.create(:service, user: user)
    end

    it "displays user's connected services" do
      get :index
      assigns[:services].should == user.services
    end
  end

  describe '#create' do
    before do
      request.env['omniauth.auth'] = omniauth_auth
      request.env['omniauth.origin'] = root_url
    end

    it 'creates a new service and associates it with the current user' do
      expect {
        post :create, :provider => 'twitter'
      }.to change(user.services, :count).by(1)
    end

    it 'saves the provider' do
      post :create, :provider => 'twitter'
      user.reload.services.first.class.name.should == "Services::Twitter"
    end

    context 'when service exists with the same uid' do
      before { Services::Twitter.create!(uid: omniauth_auth['uid'], user_id: user.id) }

      it 'doesnt create a new service' do
        expect {
        post :create, :provider => 'twitter'
      }.to_not change(Service, :count).by(1)
      end

      it 'flashes an already_authorized error with the diaspora handle for the user'  do
        post :create, :provider => 'twitter'
        flash[:error].include?(user.profile.diaspora_handle).should be_true
        flash[:error].include?( 'already authorized' ).should be_true
      end
    end

    context 'when the access-level is read-only' do
      before do 
        access_level_hash = { 'extra' => { 'access_token' => { 'response' => { 'header' => { 'x_access_level' => 'read' }}}}}
        request.env['omniauth.auth'] = omniauth_auth["info"].merge!( access_level_hash )
      end

      it 'doesnt create a new service' do
        expect {
        post :create, :provider => 'twitter'
      }.to_not change(Service, :count).by(1)
      end

      it 'flashes an read-only access error'  do
        post :create, :provider => 'twitter'
        flash[:error].include?( 'Access level is read-only' ).should be_true
      end
    end

    context 'when fetching a photo' do
      before do
        omniauth_auth
        omniauth_auth["info"].merge!({"image" => "https://service.com/fallback_lowres.jpg"})

        request.env['omniauth.auth'] = omniauth_auth
      end

      it 'does not queue a job if the profile photo is set' do
        @controller.stub!(:no_profile_image?).and_return false

        Workers::FetchProfilePhoto.should_not_receive(:perform_async)

        post :create, :provider => 'twitter'
      end

      it 'queues a job to save user photo if the photo does not exist' do
        @controller.stub!(:no_profile_image?).and_return true

        Workers::FetchProfilePhoto.should_receive(:perform_async).with(user.id, anything(), "https://service.com/fallback_lowres.jpg")

        post :create, :provider => 'twitter'
      end
    end
  end

  describe '#destroy' do
    before do
      @service1 = FactoryGirl.create(:service, :user => user)
    end

    it 'destroys a service selected by id' do
      lambda{
        delete :destroy, :id => @service1.id
      }.should change(user.services, :count).by(-1)
    end
  end
end
