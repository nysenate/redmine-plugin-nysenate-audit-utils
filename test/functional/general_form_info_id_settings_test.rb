# frozen_string_literal: true

require_relative '../test_helper'

class GeneralFormInfoIdSettingsTest < Redmine::ControllerTest
  tests SettingsController
  fixtures :users

  Config = NysenateAuditUtils::GeneralFormInfoIdConfiguration

  def setup
    @request.session[:user_id] = 1
    Setting.plugin_nysenate_audit_utils = {
      Config::SETTING_KEY => [
        { 'id' => '12', 'offices' => 'FISCAL, FOPAYROLL' },
        { 'id' => '13', 'offices' => 'PERSONNEL, FISCAL' }
      ]
    }
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = {}
  end

  test 'renders one row per mapping with a number and a text input' do
    get :plugin, params: { id: 'nysenate_audit_utils' }
    assert_response :success

    rows = css_select('#gfi-id-table tbody tr.gfi-id-row')
    assert_equal 2, rows.size
    id_input = rows.first.at_css('input[type="number"]')
    assert_equal 'settings[general_form_info_id_mappings][existing_0][id]', id_input['name']
    assert_equal '12', id_input['value']
    assert_equal 'FISCAL, FOPAYROLL', rows.first.at_css('input[type="text"]')['value']
    assert_select '#gfi-id-row-template'
    assert_select '#gfi-id-add-row'
  end

  test 'warns about offices listed under more than one id' do
    get :plugin, params: { id: 'nysenate_audit_utils' }
    assert_select '.flash.warning', text: /FISCAL/
  end

  test 'saving the form round-trips the rows' do
    post :plugin, params: {
      id: 'nysenate_audit_utils',
      settings: {
        Config::SETTING_KEY => {
          'existing_0' => { 'id' => '6', 'offices' => 'MOSUPPLY' },
          'new_0' => { 'id' => '9', 'offices' => 'MODOCOORD' }
        }
      }
    }
    assert_response :redirect

    assert_equal({ 'MOSUPPLY' => 6, 'MODOCOORD' => 9 }, Config.office_map)
  end
end
