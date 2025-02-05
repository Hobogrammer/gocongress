require 'spec_helper'

describe 'passwords' do
  let(:password) { 'asdfasdf' }
  let(:user) { create :user, :password => password }

  it 'sends reset password instructions and changes password' do
    visit new_user_session_path(year: user.year)
    click_link 'Forgot your password?'
    fill_in 'Email', with: user.email
    click_button 'Send me reset password instructions'
    current_path.should eq("/#{user.year}/sign_ups/sign_in")
    page.should have_content('You will receive an email with instructions about how to reset your password in a few minutes.')
    last_email = ActionMailer::Base.deliveries.last
    last_email.to.should include(user.email)
    mail_body = last_email.body.to_s
    token = mail_body[/reset_password_token=([^"]+)/, 1]
    visit edit_user_password_url(year: user.year, reset_password_token: token)
    new_password = 'whocares'
    fill_in 'Password', with: new_password
    fill_in 'Password confirmation', with: new_password
    click_button 'Change my password'
    page.should have_content('Your password was changed. You are now signed in.')
  end
end
