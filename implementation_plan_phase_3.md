# Fase 3: Lead Automation & Notifications

## Overview
This phase focuses on automating the lead nurturing process and ensuring immediate notifications for the admin team. We will leverage Sidekiq for background processing and ActionMailer for email delivery.

## Prerequisites
- [x] **Sidekiq Gem**: Verified in `Gemfile`.
- [x] **Action Mailer**: Standard in Rails.
- [ ] **Redis**: Required for Sidekiq. (Assuming available or will use `async` adapter for dev if necessary, but Sidekiq provided implies Redis usage).
- [ ] **Mail Configuration**: Needs to be set up in `development.rb` (currently `raise_delivery_errors = false`).

## Goals
1.  **Lead Notification Email**: Send an email to the admin/broker whenever a new lead is created.
2.  **Welcome Email**: Send a "Thank you" email to the lead immediately after signup.
3.  **Background Processing**: Ensure emails are sent asynchronously using Sidekiq to avoid blocking the request.

## Implementation Steps

### 1. Mailer Setup
*   Generate `LeadMailer`.
*   Create templates for:
    *   `new_lead_notification` (To Admin)
    *   `welcome_lead` (To User)
*   Preview templates for verification.

### 2. Configuration
*   Configure `config.action_mailer.default_url_options` in environments.
*   Configure `config.active_job.queue_adapter = :sidekiq`.
*   (Optional) Set up LetterOpener for development preview.

### 3. Trigger Logic
*   Call `LeadMailer.with(lead: @lead).new_lead_notification.deliver_later` in `LeadsController#create` (or wherever leads are generated, possibly `api/v1` or public `leads_controller`).
*   Call `LeadMailer.with(lead: @lead).welcome_lead.deliver_later`.

### 4. Verification
*   Trigger a lead creation.
*   Verify Sidekiq job enqueue.
*   Check email content (via logs or LetterOpener).
