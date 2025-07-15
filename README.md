# BACHelp Packet Creation Plugin

A Redmine plugin for creating ticket packets containing PDF views and attachments for auditing purposes.

## Features

- Create packet button on ticket view
- Generate zip file containing ticket PDF and all attachments
- Designed for audit workflow support

## Installation

1. Copy plugin to `plugins/bachelp_packet_creation` directory
2. Run `bundle exec rake redmine:plugins:migrate`
3. Restart Redmine

## Requirements

- Redmine 5.0.0 or higher