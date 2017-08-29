# coding: utf-8

require 'recastai'
require 'dotenv/load'
require 'pry'
require 'json'
require 'open-uri'


def bot(payload)
  connect = RecastAI::Connect.new(ENV['REQUEST_TOKEN'], ENV['LANGUAGE'])
  request = RecastAI::Request.new(ENV['REQUEST_TOKEN'])

  connect.handle_message(payload) do |message|
    response = request.converse_text(message.content, conversation_token: message.sender_id)

    if message.type == "payload" && (message.content.include? "search?ingredients")
      messages = select_food(message)
      connect.send_message(messages, message.conversation_id)
    elsif response.intent.slug
      if response.intent.slug == "reco_recette" || message.content == "SUGGEST_RECIPE"
        messages = send_suggestions
        connect.send_message(messages, message.conversation_id)
      else
        replies = response.replies.map{ |r| { type: 'text', content: r } }
        connect.send_message(replies, message.conversation_id)
      end
    end

  end
  200
end

def send_suggestions
  url = 'https://www.foodmama.fr/api/v1/suggest'
  suggest_serialized = open(url).read
  suggest = JSON.parse(suggest_serialized)
  content = []
  suggest["recipes"].each do |recipe|
          content << {
            title: "#{recipe["title"]}",
            imageUrl: "#{recipe["imageUrl"]}",
            buttons: [
              {
                title: 'Voir plus',
                value: "https://www.foodmama.fr#{recipe['recipeUrl']}",
                type: 'web_url'
              },
              {
                type: 'postback',
                title: 'Faire cette recette',
                value: "http://www.foodmama.fr/api/v1/search?ingredients[]=#{recipe["title"]}"
              }
            ]
          }
  end
  messages = [
    {
      type: 'carousel',
      content: content
    }
  ]
end

def select_food(message)
  url = URI.escape(message.content)
  search_food_serialized = open(url).read
  search_food = JSON.parse(search_food_serialized)
  food_title = search_food["recipes"][0]["title"]
  food_ingredients = search_food["recipes"][0]["ingredients"].map { |dose| "* #{dose["dose"]} #{dose["ingredient"]} #{dose["complement"]}"}.join("\n")

  messages = [
    {
      type: 'text',
      content: food_title + ":\n(🍴 2 pers.)\n" + food_ingredients
    }
  ]
end
