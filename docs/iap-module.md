# AscendKit — IAP / Subscription Assistance Module Draft

## 1. Purpose

Help users create and prepare common in-app purchase and subscription setups for App Store release workflows, without pretending commerce strategy can be fully automated.

## 2. Initial scope

### 2.1 Subscription templates
Support opinionated starter templates such as:
- weekly
- monthly
- yearly
- optional free trial template (for example 1 month)

These are templates, not mandatory business-model defaults.

### 2.2 Local definition model
Users should define product intent locally before creating remote ASC objects.

Suggested fields:
- product identifier
- product type
- subscription group
- display name
- description
- base duration
- introductory offer settings
- review notes

### 2.3 Review readiness checks
AscendKit should remind users about:
- subscription group existence
- localization completeness
- restore purchases UX expectations
- pricing readiness
- trial sanity
- review screenshot/notes if needed
- terms/privacy linkage

## 3. Non-goals initially
- advanced revenue optimization
- server entitlement infrastructure
- complex offer experimentation systems
- full analytics or paywall AB testing support

## 4. Safety principle

Creating IAP products remotely is a mutating operation and should require explicit confirmation.
