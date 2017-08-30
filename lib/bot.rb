# coding: utf-8

require 'recastai'
require 'dotenv/load'
require 'pry'
require 'json'
require 'open-uri'


def bot(payload)
  connect = RecastAI::Connect.new(ENV['REQUEST_TOKEN'], ENV['LANGUAGE'])
  request = RecastAI::Request.new(ENV['REQUEST_TOKEN'], ENV['LANGUAGE'])

  connect.handle_message(payload) do |message|
    response = request.converse_text(message.content, conversation_token: message.sender_id)
    username = URI.escape(message.message["data"]["userName"])
    sender_id = message.sender_id

    unless response.intent.nil?

      if response.intent.slug
        if response.intent.slug == "suggest-food"
          messages = send_suggestions(username, sender_id)
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "food-history"
          messages = send_history(username, sender_id)
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "search-ingredients"
          query = []
          ingredients = response.entities.select { |entity| entity.name == "ingredient" }
          emojis = response.entities.select { |entity| entity.name == "emoji" }
          if (ingredients.any?)
            ingredients.each { |entity| query << "ingredients[]=#{entity.value}" }
            query = query.join("&")
            messages = search_food(query)
            connect.send_message(messages, message.conversation_id)
          elsif (emojis.any?)
            emojis.each { |entity| query << "ingredients[]=#{entity.description}" }
            query = query.join("&")
            messages = search_food(query)
            connect.send_message(messages, message.conversation_id)
          end

        elsif response.intent.slug == "search-by-id"
          messages = select_food(response.get_memory('recette_id').value.gsub(/[^0-9,.]/, ""), username, sender_id)
          connect.send_message(messages, message.conversation_id)

        else
          replies = response.replies.map{ |r| { type: 'text', content: r } }
          connect.send_message(replies, message.conversation_id)
        end
      end

    else
      replies = response.replies.map{ |r| { type: 'text', content: r } }
      connect.send_message(replies, message.conversation_id)
    end
  end
  200
end

def send_suggestions(username, sender_id)
  url = "https://www.foodmama.fr/api/v1/suggest?sender_id=#{sender_id}&userName=#{username}"
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
                value: "Je cherche la recette id_#{recipe['recipeId']}"
              }
            ]
          }
  end
  messages = [
    {
      type: 'carousel',
      content: content
    },
    {
      type: 'quickReplies',
      content:
      {
        title: "...",
        buttons: [
          {
            title: 'Autres suggestions ?',
            value: 'Donnes-moi des idées'
          },
          {
            title: 'Demander à Mama',
            value: 'Je veux chercher une recette'
          }
        ]
      }
    }
  ]
end

def search_food(query)
  url = "http://www.foodmama.fr/api/v1/search?#{query}"
  search_serialized = open(url).read
  suggest = JSON.parse(search_serialized)
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
                value: "Je cherche la recette id_#{recipe['recipeId']}"
              }
            ]
          }
  end
  if content.empty?
     messages = [
      {
        type: 'text',
        content: "Oops, Mama n'a pas ce que tu demandes 😵"
      },
      {
        type: 'quickReplies',
        content:
        {
          title: "...",
          buttons: [
            {
              title: 'Des suggestions ?',
              value: 'Donnes-moi des idées'
            },
            {
              title: 'Chercher ?',
              value: 'Je veux chercher une recette'
            }
          ]
        }
      }
    ]
  else messages = [
          {
            type: 'carousel',
            content: content
          }
        ]
  end
end

def select_food(recipeId, username, sender_id)
  url = "https://www.foodmama.fr/api/v1/select?recipe=#{recipeId}&sender_id=#{sender_id}&userName=#{username}"
  selected_food_serialized = open(url).read
  selected_food = JSON.parse(selected_food_serialized)
  selected_food_ingredients = selected_food["ingredients"].map { |dose| "* #{dose["dose"]} #{dose["ingredient"]} #{dose["complement"]}"}.join("\n")
  return messages = [
    {
      type: 'text',
      content: selected_food["title"] + ":\n(🍴 2 pers.)\n" + selected_food_ingredients,
    },
    {
      type: 'quickReplies',
      content:
      {
        title: "Besoin d'autre chose?",
        buttons: [
          {
            title: 'Non merci !',
            value: 'merci Mama'
          },
         {
            title: 'Suggestions ?',
            value: 'Donnes-moi des idées'
          },
          {
            title: 'Chercher ?',
            value: 'Je veux chercher une recette'
          }
        ]
      }
    }
  ]
end

def send_history(username, sender_id)
  url = "https://www.foodmama.fr/api/v1/history?sender_id=#{sender_id}&userName=#{username}"
  history_serialized = open(url).read
  history = JSON.parse(history_serialized)
  content = []
  history["recipes"].each do |recipe|
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
                  value: "Je cherche la recette id_#{recipe['recipeId']}"
                }
              ]
            }
    end
  if content.empty?
     messages = [
      {
        type: 'text',
        content: "Oops, tu n'as pas encore fait de recettes 😱😱😱!"
      },
      {
        type: 'quickReplies',
        content:
        {
          title: "...",
          buttons: [
            {
              title: 'Des suggestions ?',
              value: 'Donnes-moi des idées'
            },
            {
              title: 'Chercher ?',
              value: 'Je veux chercher une recette'
            }
          ]
        }
      }
    ]
  else messages = [
          {
            type: 'carousel',
            content: content
          }
        ]
  end
end
