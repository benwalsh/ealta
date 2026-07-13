module Api
  # GET /api/directory?sort=&scope= — the Directory tab (the species browser).
  # "heard" = the life list; "all" = the whole illustrated library, with un-heard
  # species carried as zero-count entries so they show greyed but browsable.
  class DirectoryController < BaseController
    SORTS = %w[count recent alpha].freeze

    def show
      sort = SORTS.include?(params[:sort]) ? params[:sort] : 'count'
      scope = params[:scope] == 'all' ? 'all' : 'heard'
      today = Detection.tally_for(Time.zone.today).to_h { |t| [t.sci_name, t.count] }
      species = sorted(entries(scope), sort).map { |e| life_json(e).merge(today: today[e.sci_name].to_i) }
      render json: { sort: sort, scope: scope, species: species }
    end

    private

    def entries(scope)
      heard = Detection.life_list
      return heard unless scope == 'all'

      # The UNION of the life list and the illustrated catalogue — heard birds must never
      # drop out of "all" just because the profile's catalogue doesn't carry them (a
      # small/new profile may have no catalogue at all, which used to make "all" come
      # back empty while "heard" had birds).
      seen = heard.index_by(&:sci_name)
      heard + (SpeciesCatalog.all_sci - seen.keys).map { |sci| Detection::LifeEntry.new(sci, 0, nil, nil) }
    end

    # Un-heard birds sort to the bottom (alphabetical among themselves), except in
    # a→z where they interleave by name.
    def sorted(list, sort)
      seen, unseen = list.partition { |entry| entry.count.positive? } # rubocop:disable Style/CollectionQuerying
      case sort
      when 'recent' then seen.sort_by(&:last_seen).reverse + alpha(unseen)
      when 'alpha'  then alpha(list)
      else seen.sort_by(&:count).reverse + alpha(unseen)
      end
    end

    def alpha(list)
      list.sort_by { |entry| (entry.name.ga || entry.name.en).downcase }
    end
  end
end
