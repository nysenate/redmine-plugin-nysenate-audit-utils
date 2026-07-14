source 'https://rubygems.org'

group :test do
  gem 'webmock', require: false
  # E2E/system tests drive a real browser via Playwright instead of Selenium.
  # Requires the Playwright CLI/browser binary: `npx playwright install chromium`.
  gem 'capybara-playwright-driver', require: false
end
