require 'rails_helper'
require 'rake'

# The false-positive pruner. Its whole reason to exist is to be SAFE: a dry run by default that
# touches nothing, and a species-scoped delete (detections + their events, never other birds)
# only when CONFIRM=DELETE is passed.
RSpec.describe 'detections:remove_species' do # rubocop:disable RSpec/DescribeClass -- a rake task, not a class
  # Load the app's tasks once, and re-enable before each example so the task can be invoked again
  # (Rake tasks run at most once per process otherwise). Safe here: this hook creates no records —
  # it only registers the task definitions — so there is no fixture state to leak.
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll -- loads rake tasks only, no DB state
    Rake.application = Rake::Application.new
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let(:task) { Rake::Task['detections:remove_species'] }

  around do |example|
    task.reenable
    example.run
    ENV.delete('SPECIES')
    ENV.delete('CONFIRM')
  end

  def run_task
    # The task prints its report; capture it so specs can assert on what it said.
    output = StringIO.new
    $stdout = output
    task.invoke
    output.string
  ensure
    $stdout = STDOUT
  end

  before do
    # A false positive to prune, a real bird that must survive, and an event for each so we can
    # prove the event of the pruned species goes and the event of the kept species stays.
    create_list(:detection, 3, Sci_Name: 'Grus grus', Com_Name: 'Common Crane')
    create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    create(:event, event_type: 'rarity', sci_name: 'Grus grus')
    create(:event, event_type: 'seasonal', sci_name: 'Erithacus rubecula')
  end

  it 'deletes nothing by default — a dry run only counts and reports' do
    ENV['SPECIES'] = 'Common Crane'
    out = run_task

    expect(out).to include('dry run')
    expect(out).to match(/Common Crane\s+3 detections,\s+1 events/)
    expect(Detection.where(Sci_Name: 'Grus grus').count).to eq(3) # untouched
    expect(Event.where(sci_name: 'Grus grus').count).to eq(1)
  end

  it 'removes the species detections AND its events when CONFIRM=DELETE, and nothing else' do
    ENV['SPECIES'] = 'Common Crane'
    ENV['CONFIRM'] = 'DELETE'
    out = run_task

    expect(out).to include('deleted 3 detections and 1 events')
    expect(Detection.where(Sci_Name: 'Grus grus')).to be_empty
    expect(Event.where(sci_name: 'Grus grus')).to be_empty
    # The real bird and its event are left completely alone.
    expect(Detection.where(Sci_Name: 'Erithacus rubecula').count).to eq(1)
    expect(Event.where(sci_name: 'Erithacus rubecula').count).to eq(1)
  end

  it 'resolves a species by its scientific name too' do
    ENV['SPECIES'] = 'grus grus'
    ENV['CONFIRM'] = 'DELETE'
    run_task
    expect(Detection.where(Sci_Name: 'Grus grus')).to be_empty
  end

  it 'reports a name that matches nothing instead of failing, and deletes nothing for it' do
    ENV['SPECIES'] = 'Common Crane, Nonexistent Bird'
    ENV['CONFIRM'] = 'DELETE'
    out = run_task
    expect(out).to match(/Nonexistent Bird\s+no rows match/)
    expect(out).to include('deleted 3 detections and 1 events') # the real match still went
  end
end
