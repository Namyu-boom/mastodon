# frozen_string_literal: true

class SocialClassicBrandingController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    response.headers['Cache-Control'] = 'public, max-age=0, must-revalidate'
    render plain: stylesheet, content_type: 'text/css; charset=utf-8'
  end

  private

  def stylesheet
    <<~CSS
      :root,
      [data-color-scheme="light"] {
        --social-classic-theme-color: #{theme_color(:light)};
        --social-classic-logo: #{image_value(:social_classic_light_logo)};
        --social-classic-default-logo-opacity: #{upload_present?(:social_classic_light_logo) ? 0 : 1};
        --social-classic-background: #{image_value(:social_classic_light_background)};
      }

      [data-color-scheme="dark"] {
        --social-classic-theme-color: #{theme_color(:dark)};
        --social-classic-logo: #{image_value(:social_classic_dark_logo)};
        --social-classic-default-logo-opacity: #{upload_present?(:social_classic_dark_logo) ? 0 : 1};
        --social-classic-background: #{image_value(:social_classic_dark_background)};
      }
    CSS
  end

  def theme_color(mode)
    value = Setting.public_send("social_classic_#{mode}_theme_color")
    value.match?(/\A#[0-9a-f]{6}\z/i) ? value : '#1d9bf0'
  end

  def image_value(var)
    upload = site_upload(var)
    return 'none' if upload.nil?

    "url(#{upload.file.url.to_json})"
  end

  def upload_present?(var)
    site_upload(var).present?
  end

  def site_upload(var)
    Rails.cache.fetch("site_uploads/#{var}") { SiteUpload.find_by(var:) }
  end
end
