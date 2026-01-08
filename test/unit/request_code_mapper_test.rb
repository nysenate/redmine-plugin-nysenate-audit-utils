# frozen_string_literal: true

require_relative '../test_helper'

class RequestCodeMapperTest < ActiveSupport::TestCase
  def setup
    @mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new
  end

  # Test Oracle / SFMS mappings
  test 'should map Oracle/SFMS Add to USRA' do
    code = @mapper.get_request_code('Add', 'Oracle / SFMS')
    assert_equal 'USRA', code
  end

  test 'should map Oracle/SFMS Delete to USRI' do
    code = @mapper.get_request_code('Delete', 'Oracle / SFMS')
    assert_equal 'USRI', code
  end

  test 'should map Oracle/SFMS Update Account & Privileges to USRU' do
    code = @mapper.get_request_code('Update Account & Privileges', 'Oracle / SFMS')
    assert_equal 'USRU', code
  end

  test 'should map Oracle/SFMS Update Privileges Only to USRU' do
    code = @mapper.get_request_code('Update Privileges Only', 'Oracle / SFMS')
    assert_equal 'USRU', code
  end

  test 'should map Oracle/SFMS Update Account Only to USRU' do
    code = @mapper.get_request_code('Update Account Only', 'Oracle / SFMS')
    assert_equal 'USRU', code
  end

  # Test AIX mappings
  test 'should map AIX Add to AIXA' do
    code = @mapper.get_request_code('Add', 'AIX')
    assert_equal 'AIXA', code
  end

  test 'should map AIX Delete to AIXI' do
    code = @mapper.get_request_code('Delete', 'AIX')
    assert_equal 'AIXI', code
  end

  test 'should map AIX Update to AIXU' do
    code = @mapper.get_request_code('Update Account & Privileges', 'AIX')
    assert_equal 'AIXU', code
  end

  # Test SFS mappings
  test 'should map SFS Add to SFSA' do
    code = @mapper.get_request_code('Add', 'SFS')
    assert_equal 'SFSA', code
  end

  test 'should map SFS Delete to SFSI' do
    code = @mapper.get_request_code('Delete', 'SFS')
    assert_equal 'SFSI', code
  end

  test 'should map SFS Update to SFSU' do
    code = @mapper.get_request_code('Update Account & Privileges', 'SFS')
    assert_equal 'SFSU', code
  end

  # Test NYSDS mappings
  test 'should map NYSDS Add to DSA' do
    code = @mapper.get_request_code('Add', 'NYSDS')
    assert_equal 'DSA', code
  end

  test 'should map NYSDS Delete to DSI' do
    code = @mapper.get_request_code('Delete', 'NYSDS')
    assert_equal 'DSI', code
  end

  test 'should map NYSDS Update to DSU' do
    code = @mapper.get_request_code('Update Account & Privileges', 'NYSDS')
    assert_equal 'DSU', code
  end

  # Test PayServ mappings
  test 'should map PayServ Add to PYSA' do
    code = @mapper.get_request_code('Add', 'PayServ')
    assert_equal 'PYSA', code
  end

  test 'should map PayServ Delete to PYSI' do
    code = @mapper.get_request_code('Delete', 'PayServ')
    assert_equal 'PYSI', code
  end

  test 'should map PayServ Update to PYSU' do
    code = @mapper.get_request_code('Update Account & Privileges', 'PayServ')
    assert_equal 'PYSU', code
  end

  # Test OGS Swiper Access mappings
  test 'should map OGS Swiper Access Add to CTRA' do
    code = @mapper.get_request_code('Add', 'OGS Swiper Access')
    assert_equal 'CTRA', code
  end

  test 'should map OGS Swiper Access Delete to CTRI' do
    code = @mapper.get_request_code('Delete', 'OGS Swiper Access')
    assert_equal 'CTRI', code
  end

  # Test reverse mapping
  test 'should reverse map USRA to Oracle/SFMS Add' do
    fields = @mapper.get_fields_from_code('USRA')
    assert_equal 'Add', fields[:account_action]
    assert_equal 'Oracle / SFMS', fields[:target_system]
  end

  test 'should reverse map AIXI to AIX Delete' do
    fields = @mapper.get_fields_from_code('AIXI')
    assert_equal 'Delete', fields[:account_action]
    assert_equal 'AIX', fields[:target_system]
  end

  test 'should reverse map SFSU to SFS Update' do
    fields = @mapper.get_fields_from_code('SFSU')
    assert_equal 'Update Account & Privileges', fields[:account_action]
    assert_equal 'SFS', fields[:target_system]
  end

  # Test edge cases
  test 'should return nil for unknown system' do
    code = @mapper.get_request_code('Add', 'Unknown System')
    assert_nil code
  end

  test 'should return nil for unknown action' do
    code = @mapper.get_request_code('Unknown Action', 'Oracle / SFMS')
    assert_nil code
  end

  test 'should return nil for blank account action' do
    code = @mapper.get_request_code('', 'Oracle / SFMS')
    assert_nil code
  end

  test 'should return nil for blank target system' do
    code = @mapper.get_request_code('Add', '')
    assert_nil code
  end

  test 'should return nil for nil account action' do
    code = @mapper.get_request_code(nil, 'Oracle / SFMS')
    assert_nil code
  end

  test 'should return nil for nil target system' do
    code = @mapper.get_request_code('Add', nil)
    assert_nil code
  end

  test 'should return nil for unknown request code in reverse mapping' do
    fields = @mapper.get_fields_from_code('UNKNOWN')
    assert_nil fields
  end

  test 'should return nil for blank request code in reverse mapping' do
    fields = @mapper.get_fields_from_code('')
    assert_nil fields
  end

  test 'should return nil for nil request code in reverse mapping' do
    fields = @mapper.get_fields_from_code(nil)
    assert_nil fields
  end

  # Test utility methods
  test 'should return all request codes sorted' do
    codes = @mapper.all_codes
    assert codes.is_a?(Array)
    assert codes.include?('USRA')
    assert codes.include?('AIXA')
    assert codes.include?('SFSA')
    assert_equal codes, codes.sort
  end

  test 'should return all target systems sorted' do
    systems = @mapper.all_target_systems
    assert systems.is_a?(Array)
    assert systems.include?('Oracle / SFMS')
    assert systems.include?('AIX')
    assert systems.include?('SFS')
    assert_equal systems, systems.sort
  end

  test 'should return account actions for AIX' do
    actions = @mapper.account_actions_for_system('AIX')
    assert actions.is_a?(Array)
    assert actions.include?('Add')
    assert actions.include?('Delete')
    assert actions.include?('Update Account & Privileges')
  end

  test 'should return empty array for unknown system' do
    actions = @mapper.account_actions_for_system('Unknown System')
    assert_equal [], actions
  end

  test 'should return empty array for blank system' do
    actions = @mapper.account_actions_for_system('')
    assert_equal [], actions
  end

  # Test custom mappings
  test 'should support custom mappings' do
    custom_mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new(
      'Custom System' => {
        'Add' => 'CSTA',
        'Delete' => 'CSTI'
      }
    )

    code = custom_mapper.get_request_code('Add', 'Custom System')
    assert_equal 'CSTA', code

    fields = custom_mapper.get_fields_from_code('CSTA')
    assert_equal 'Add', fields[:account_action]
    assert_equal 'Custom System', fields[:target_system]
  end

  test 'should merge custom mappings with defaults' do
    custom_mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new(
      'Custom System' => {
        'Add' => 'CSTA'
      }
    )

    # Should still have default mappings
    code = custom_mapper.get_request_code('Add', 'Oracle / SFMS')
    assert_equal 'USRA', code

    # Should also have custom mapping
    custom_code = custom_mapper.get_request_code('Add', 'Custom System')
    assert_equal 'CSTA', custom_code
  end

  test 'should allow overriding default mappings' do
    custom_mapper = NysenateAuditUtils::RequestCodes::RequestCodeMapper.new(
      'Oracle / SFMS' => {
        'Add' => 'CUSTOM'
      }
    )

    code = custom_mapper.get_request_code('Add', 'Oracle / SFMS')
    assert_equal 'CUSTOM', code
  end
end
