module Admin::MetaCampaignsHelper
  def meta_campaign_cost(spend, results)
    return "—" unless spend && results.to_i.positive?

    number_to_currency(spend.to_f / results, unit: "R$", separator: ",", delimiter: ".")
  end

  def meta_campaign_rate(results, total)
    return "—" unless total.to_i.positive?

    number_to_percentage(results.to_f / total * 100, precision: 1, separator: ",")
  end
end
