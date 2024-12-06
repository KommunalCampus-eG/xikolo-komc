# frozen_string_literal: true

require 'spec_helper'

describe ApplicationController, type: :controller do
  subject { resource }

  let(:resource) { Restify.new(:test).get.value }

  it { is_expected.to have_relation :user_tests }
  it { is_expected.to have_relation :test_groups }
  it { is_expected.to have_relation :trials }
  it { is_expected.to have_relation :metrics }
end
