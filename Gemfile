source 'https://rubygems.org'

# Formatted Excel (.xlsx) report exports. Pure Ruby; depends on rubyzip which
# Redmine already vendors.
gem 'caxlsx'

group :test do
  gem 'webmock', require: false
  # E2E/system tests drive a real browser via Playwright instead of Selenium.
  # Requires the Playwright CLI/browser binary: `npx playwright install chromium`.
  gem 'capybara-playwright-driver', require: false
end
