# encoding: utf-8
# copyright: 2015, The Authors
# license: All rights reserved
control 'whichgordon' do
  describe gordon_config do
    its('version') { should eq('2.0') }
  end

  describe resource('profile_d', 'gordon_config') do
    its('version') { should eq('2.0') }
  end

  describe resource('profile_c', 'gordon_config') do
    its('version') { should eq('1.0') }
  end
end
