require 'test_helper'

class DmailTest < ActiveSupport::TestCase
  context "A dmail" do
    setup do
      @user = FactoryBot.create(:user)
      CurrentUser.user = @user
      CurrentUser.ip_addr = "1.2.3.4"
      ActionMailer::Base.delivery_method = :test
      ActionMailer::Base.perform_deliveries = true
      ActionMailer::Base.deliveries = []
    end

    teardown do
      CurrentUser.user = nil
    end

    context "spam" do
      setup do
        Dmail.any_instance.stubs(:spam?).returns(true)
        @spammer = create(:user)
        @recipient = create(:user)
      end

      should "not validate" do
        assert_difference("Dmail.count", 2) do
          Dmail.create_split(from: @spammer, to: @recipient, title: "spam", body: "wonderful spam")
          assert(@recipient.dmails.last.is_spam?)
        end
      end

      should "autoban spammers after sending spam to N distinct users" do
        users = create_list(:user, Dmail::AUTOBAN_THRESHOLD)
        users.each do |user|
          Dmail.create_split(from: @spammer, to: user, title: "spam", body: "wonderful spam")
        end

        assert_equal(true, Dmail.is_spammer?(@spammer))
        assert_equal(true, @spammer.reload.is_banned)
        assert_equal(1, @spammer.bans.count)
        assert_match(/Spambot./, @spammer.bans.last.reason)
        assert_match(/Spambot./, @spammer.feedback.last.body)
      end
    end

    context "from a banned user" do
      setup do
        @user.update_attribute(:is_banned, true)
      end

      should "not validate" do
        dmail = FactoryBot.build(:dmail, :title => "xxx", :owner => @user)
        dmail.save
        assert_equal(1, dmail.errors.size)
        assert_equal(["Sender is banned and cannot send messages"], dmail.errors.full_messages)
      end
    end

    context "search" do
      should "return results based on title contents" do
        dmail = FactoryBot.create(:dmail, :title => "xxx", :owner => @user)

        matches = Dmail.search(title_matches: "x*")
        assert_equal([dmail.id], matches.map(&:id))

        matches = Dmail.search(title_matches: "X*")
        assert_equal([dmail.id], matches.map(&:id))

        matches = Dmail.search(message_matches: "xxx")
        assert_equal([dmail.id], matches.map(&:id))

        matches = Dmail.search(message_matches: "aaa")
        assert(matches.empty?)
      end

      should "return results based on body contents" do
        dmail = FactoryBot.create(:dmail, :body => "xxx", :owner => @user)
        matches = Dmail.search(message_matches: "xxx")
        assert(matches.any?)
        matches = Dmail.search(message_matches: "aaa")
        assert(matches.empty?)
      end
    end

    should "should parse user names" do
      dmail = FactoryBot.build(:dmail, :owner => @user)
      dmail.to_id = nil
      dmail.to_name = @user.name
      assert(dmail.to_id == @user.id)
    end

    should "construct a response" do
      dmail = FactoryBot.create(:dmail, :owner => @user)
      response = dmail.build_response
      assert_equal("Re: #{dmail.title}", response.title)
      assert_equal(dmail.from_id, response.to_id)
      assert_equal(dmail.to_id, response.from_id)
    end

    should "create a copy for each user" do
      @new_user = FactoryBot.create(:user)
      assert_difference("Dmail.count", 2) do
        Dmail.create_split(:to_id => @new_user.id, :title => "foo", :body => "foo")
      end
    end

    should "record the creator's ip addr" do
      dmail = FactoryBot.create(:dmail, owner: @user)
      assert_equal(CurrentUser.ip_addr, dmail.creator_ip_addr.to_s)
    end

    should "send an email if the user wants it" do
      user = create(:user, receive_email_notifications: true)
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        create(:dmail, to: user, owner: user, body: "test [[tagme]]")
      end
    end

    should "create only one message for a split response" do
      user = FactoryBot.create(:user, :receive_email_notifications => true)
      assert_difference("ActionMailer::Base.deliveries.size", 1) do
        Dmail.create_split(:to_id => user.id, :title => "foo", :body => "foo")
      end
    end

    should "notify the recipient he has mail" do
      recipient = create(:user)

      Dmail.create_split(title: "hello", body: "hello", to_id: recipient.id)
      assert_equal(1, recipient.reload.unread_dmail_count)

      recipient.dmails.unread.last.update!(is_read: true)
      assert_equal(0, recipient.reload.unread_dmail_count)
    end

    context "that is automated" do
      setup do
        @bot = FactoryBot.create(:user)
        User.stubs(:system).returns(@bot)
      end

      should "only create a copy for the recipient" do
        Dmail.create_automated(to: @user, title: "test", body: "test")

        assert @user.dmails.exists?(from: @bot, title: "test", body: "test")
        assert !@bot.dmails.exists?(from: @bot, title: "test", body: "test")
      end

      should "fail gracefully if recipient doesn't exist" do
        assert_nothing_raised do
          dmail = Dmail.create_automated(to_name: "this_name_does_not_exist", title: "test", body: "test")
          assert_equal(["must exist"], dmail.errors[:to])
        end
      end
    end

    context "during validation" do
      subject { FactoryBot.build(:dmail) }

      should_not allow_value(" ").for(:title)
      should_not allow_value(" ").for(:body)
      should_not allow_value(nil).for(:to)
      should_not allow_value(nil).for(:from)
      should_not allow_value(nil).for(:owner)
    end
  end
end
