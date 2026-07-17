# The account panel's data: the daily-letter (roundup) state and the species picker.
# The follow LIST itself is deliberately NOT here — the SPA reads followed sci_names from
# its own favourites state (FollowProvider) and resolves names from `species`, so follow
# state has a single source of truth and never drifts from the /favourites toggle.
module AccountSerializer
  module_function

  def call(user)
    {
      roundup: user.subscriptions.active.exists?(alert_type: 'roundup'),
      species: species_picker
    }
  end

  # The 206 Irish (BoCCI) species, bilingual, sorted by English name — a sane picker
  # rather than all ~6000 BirdNET species. Mirrors SubscriptionsController#species_options.
  def species_picker
    list = Conservation.species.map do |sci|
      name = BirdName.lookup(sci)
      { sci: sci, en: name.en, ga: name.ga }
    end
    list.sort_by { |h| h[:en] }
  end
end
