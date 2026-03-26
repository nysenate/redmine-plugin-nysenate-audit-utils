# frozen_string_literal: true

# Sample vendor data for testing tracked user functionality
# This seed file can be run manually via Rails console or as part of test setup

puts 'Creating sample vendors...'

vendors = [
  {
    user_type: 'Vendor',
    user_id: 'V1',
    name: 'Acme Corporation',
    email: 'contact@acmecorp.com',
    phone: '555-0101',
    location:'Building A',
    status: 'Active'
  },
  {
    user_type: 'Vendor',
    user_id: 'V2',
    name: 'Widget Industries LLC',
    email: 'info@widgetind.com',
    phone: '555-0102',
    location:'Building B',
    status: 'Active'
  },
  {
    user_type: 'Vendor',
    user_id: 'V3',
    name: 'Tech Solutions Inc',
    email: 'sales@techsolutions.com',
    phone: '555-0103',
    uid: 'techsol',
    location:'Remote',
    status: 'Active'
  },
  {
    user_type: 'Vendor',
    user_id: 'V4',
    name: 'Global Services Group',
    email: 'hello@globalservices.com',
    phone: '555-0104',
    location:'Building C',
    status: 'Inactive'
  },
  {
    user_type: 'Vendor',
    user_id: 'V5',
    name: 'Enterprise Systems Co',
    email: 'contact@entsys.com',
    phone: '555-0105',
    uid: 'entsys',
    location:'Building A',
    status: 'Active'
  },
  {
    user_type: 'Vendor',
    user_id: 'V6',
    name: 'Premier Consulting',
    email: 'info@premierconsult.com',
    phone: '555-0106',
    location:'Building D',
    status: 'Active'
  },
  {
    user_type: 'Vendor',
    user_id: 'V7',
    name: 'DataTech Partners',
    email: 'contact@datatechpartners.com',
    phone: '555-0107',
    location:'Building B',
    status: 'Inactive'
  },
  {
    user_type: 'Vendor',
    user_id: 'V8',
    name: 'Cloud Services Ltd',
    email: 'support@cloudservices.com',
    phone: '555-0108',
    uid: 'cloudserv',
    location:'Remote',
    status: 'Active'
  }
]

vendors.each do |vendor_attrs|
  vendor = TrackedUser.find_or_create_by(
    user_type: vendor_attrs[:user_type],
    user_id: vendor_attrs[:user_id]
  ) do |v|
    v.assign_attributes(vendor_attrs)
  end

  if vendor.persisted?
    puts "  ✓ Created vendor: #{vendor.name} (#{vendor.user_id})"
  else
    puts "  ✗ Failed to create vendor: #{vendor_attrs[:name]} - #{vendor.errors.full_messages.join(', ')}"
  end
end

puts "Finished! Created #{TrackedUser.vendors.count} vendors (#{TrackedUser.active.count} active, #{TrackedUser.inactive.count} inactive)"
