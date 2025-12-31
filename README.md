# NY Senate Audit Utils Plugin

A Redmine plugin providing audit utilities for the New York State Senate, including ticket packet creation and other audit workflow tools.

## Features

### Packet Creation
- **Individual Packet Creation**: Create packet button on ticket view for single issues
- **Bulk Packet Creation**: Context menu option for creating multi-packet from selected issues
- **Context Menu Integration**: Right-click context menu options with proper Redmine sprite icons
- Generate zip file containing ticket PDF and all attachments
- Designed for audit workflow support

## Installation

1. Copy plugin to `plugins/nysenate_audit_utils` directory
2. Run `bundle exec rake redmine:plugins:migrate`
3. Restart Redmine

## Requirements

- Redmine 5.0.0 or higher