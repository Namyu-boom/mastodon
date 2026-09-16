# frozen_string_literal: true

class Admin::Settings::SocialClassicBrandingController < Admin::SettingsController
  private

  def after_update_redirect_path
    admin_settings_social_classic_branding_path
  end
end
