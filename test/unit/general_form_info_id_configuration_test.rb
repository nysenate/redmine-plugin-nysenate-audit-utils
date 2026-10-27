# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class GeneralFormInfoIdConfigurationTest < ActiveSupport::TestCase
  Config = NysenateAuditUtils::GeneralFormInfoIdConfiguration

  def setup
    Setting.plugin_nysenate_audit_utils = {}
  end

  def teardown
    Setting.plugin_nysenate_audit_utils = {}
  end

  def configure(rows)
    Setting.plugin_nysenate_audit_utils = { Config::SETTING_KEY => rows }
  end

  test 'rows normalizes the index-keyed hash the settings form saves' do
    configure(
      'existing_0' => { 'id' => '6', 'offices' => 'MOSUPPLY' },
      'new_0' => { 'id' => '12', 'offices' => 'FISCAL, FOPAYROLL' }
    )
    assert_equal %w[6 12], Config.rows.pluck('id')
  end

  test 'rows sorts by numeric id, putting rows without a numeric id last' do
    configure([
                { 'id' => '', 'offices' => 'BLANK' },
                { 'id' => '14', 'offices' => 'MAJSENIOR' },
                { 'id' => '6', 'offices' => 'MOSUPPLY' },
                { 'id' => '10', 'offices' => 'MOSHOP' }
              ])
    assert_equal ['6', '10', '14', ''], Config.rows.pluck('id')
  end

  test 'rows is empty when nothing is configured' do
    assert_equal [], Config.rows
  end

  test 'office_map splits comma-separated offices and maps them to integer ids' do
    configure([{ 'id' => '12', 'offices' => 'FISCAL, FOPAYROLL' }, { 'id' => '13', 'offices' => 'PERSONNEL' }])
    assert_equal({ 'FISCAL' => 12, 'FOPAYROLL' => 12, 'PERSONNEL' => 13 }, Config.office_map)
  end

  test 'office_map skips rows with a blank or non-numeric id and blank offices' do
    configure([
                { 'id' => '', 'offices' => 'MOSUPPLY' },
                { 'id' => 'abc', 'offices' => 'MOPURCHASE' },
                { 'id' => '9', 'offices' => ' , MODOCOORD,, ' },
                { 'id' => '10', 'offices' => '' }
              ])
    assert_equal({ 'MODOCOORD' => 9 }, Config.office_map)
  end

  test 'office_map keeps the first id for an office listed twice' do
    configure([{ 'id' => '7', 'offices' => 'MODIRECTOR' }, { 'id' => '10', 'offices' => 'modirector' }])
    assert_equal({ 'MODIRECTOR' => 7 }, Config.office_map)
    assert_equal ['MODIRECTOR'], Config.duplicate_offices
  end

  test 'lookup matches the whole office case-insensitively, ignoring surrounding whitespace' do
    configure([{ 'id' => '13', 'offices' => 'Personnel' }])
    assert_equal 13, Config.lookup(' personnel ')
    assert_nil Config.lookup('PERSONNEL OFFICE')
    assert_nil Config.lookup('RIVERA')
    assert_nil Config.lookup(nil)
    assert_nil Config.lookup('')
  end

  test 'defaults cover the known offices and exclude MODIRECTOR' do
    configure(Config::DEFAULT_ROWS)
    assert_equal 6, Config.lookup('MOSUPPLY')
    assert_equal 10, Config.lookup('MOINVREC')
    assert_equal 14, Config.lookup('SECOFSEN')
    assert_nil Config.lookup('MODIRECTOR')
    assert_empty Config.duplicate_offices
  end

  test 'migration seeds the defaults only when the key is missing' do
    require File.expand_path('../../db/migrate/010_set_default_general_form_info_id_mappings', __dir__)
    migration = SetDefaultGeneralFormInfoIdMappings.new
    migration.verbose = false

    Setting.plugin_nysenate_audit_utils = { 'ess_base_url' => 'http://ess' }
    migration.up
    Setting.clear_cache
    assert_equal Config::DEFAULT_ROWS, Config.rows
    assert_equal 'http://ess', Setting.plugin_nysenate_audit_utils['ess_base_url']

    configure([{ 'id' => '99', 'offices' => 'CUSTOM' }])
    migration.up
    Setting.clear_cache
    assert_equal [{ 'id' => '99', 'offices' => 'CUSTOM' }], Config.rows
  end
end
