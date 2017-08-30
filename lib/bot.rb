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
        if response.intent.slug == "get-help"
          messages = send_options
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "suggest-food"
          messages = send_suggestions(username, sender_id)
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "select-search"
          messages = send_search_options
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "food-history"
          messages = send_history(username, sender_id)
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "search-title"
          query = "ingredients[]=" + response.source
          messages = search_food(query)
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

        elsif response.intent.slug == "banned-ingredients"
          messages = send_banned(username, sender_id)
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "unban-by-title"
          ingredient = response.source.gsub(/\AJ'aime cet ingredient id_/, '')
          messages = unban_ingredient(ingredient, username, sender_id)
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "need-mama"
          messages = send_need_something_else
          connect.send_message(messages, message.conversation_id)

        elsif response.intent.slug == "welcome"
          messages = send_welcome_message
          connect.send_message(messages, message.conversation_id)

         elsif response.intent.slug == "greetings"
          messages = send_need_something
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
      type: 'text',
      content: "Mama te propose 2 bonnes idées :"
    },
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
            title: 'Chercher une recette',
            value: 'activer la recherche'
          }
        ]
      }
    }
  ]
end

def search_food(query)
  encoded_url = URI.encode("http://www.foodmama.fr/api/v1/search?#{query}")
  url = URI.parse(encoded_url)
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
              value: 'activer la recherche'
            }
          ]
        }
      }
    ]
  else messages = [
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
                  title: 'Chercher autre chose',
                  value: 'activer la recherche'
                },
                {
                  title: 'Des suggestions ?',
                  value: 'Donnes-moi des idées'
                }
              ]
            }
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
            value: 'activer la recherche'
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
              value: 'activer la recherche'
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

def send_options
  messages = [
      {
        type: 'quickReplies',
        content:
        {
          title: "Comment puis-je t'aider ?",
          buttons: [
            {
              title: 'Des suggestions ?',
              value: 'Donnes-moi des idées'
            },
            {
              title: 'Chercher ?',
              value: 'activer la recherche'
            }
          ]
        }
      }
    ]
end

def send_search_options
  messages = [
      {
        type: 'quickReplies',
        content:
        {
          title: "Que souhaites-tu chercher ?",
          buttons: [
            {
              title: 'par ingrédients',
              value: 'activer la recherche par ingrédients'
            },
            {
              title: 'par nom',
              value: 'activer la recherche par nom ou par titre'
            }
          ]
        }
      }
    ]
end

def send_banned(username, sender_id)
  url = "https://www.foodmama.fr/api/v1/banned?sender_id=#{sender_id}&userName=#{username}"
  banned_serialized = open(url).read
  banned = JSON.parse(banned_serialized)
  content = []
  banned["ingredients"].each do |ingredient|
            content << {
              title: "#{ingredient["title"]}",
              imageUrl: "#{ingredient["imageUrl"]}",
              buttons: [
                {
                  type: 'postback',
                  title: 'Retirer de la liste',
                  value: "J'aime cet ingredient id_#{ingredient["title"]}"
                }
              ]
            }
    end
  if content.empty?
     messages = [
      {
        type: 'text',
        content: "Il n'y a rien ici, on dirait que tu aimes tout 🥕🍖🧀🍑🍞🍄🥒!!"
      },
      {
        type: 'quickReplies',
        content:
        {
          title: "Est-ce qu'il y a des ingrédients que tu n'aimes pas ?",
          buttons: [
            {
              title: 'Oui 🤢',
              value: 'Bannir des ingrédients'
            },
            {
              title: "Non, je t'ai déjà tout dit !",
              value: "Mama peut encore aider"
            }
          ]
        }
      }
    ]
  else messages = [
      {
        type: 'text',
        content: "Voici les ingrédients que tu n'aimes pas:"
      },
      {
        type: 'carousel',
        content: content
      },
      {
        type: 'quickReplies',
        content:
        {
          title: "Est-ce qu'il y a d'autres ingrédients que tu n'aimes pas ?",
          buttons: [
            {
              title: 'Oui 🤢',
              value: 'Bannir des ingrédients'
            },
            {
              title: "Non, c'est bon !",
              value: "Mama peut encore aider"
            }
          ]
        }
      }
    ]
  end
end

def send_need_something_else
  messages = [
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
            value: 'activer la recherche'
          }
        ]
      }
    }
  ]
end

def send_need_something
  messages = [
    {
      type: 'quickReplies',
      content:
      {
        title: "Bonjour ! Comment puis-je t'aider ?",
        buttons: [
          {
            title: 'Voir des suggestions',
            value: 'Donnes-moi des idées'
          },
          {
            title: 'Chercher une recette',
            value: 'activer la recherche'
          }
        ]
      }
    }
  ]
end

def unban_ingredient(title, username, sender_id)
  url = "https://www.foodmama.fr/api/v1/unban?ingredient=#{title}&sender_id=#{sender_id}&userName=#{username}"
  open(url).read
  messages = [
        {
          type: 'text',
          content: "Ok !"
        },
      {
        type: 'quickReplies',
        content:
        {
          title: "...",
          buttons: [
            {
              title: 'Afficher mes préférences',
              value: "ingrédients que je n'aime pas"
            }
          ]
        }
      }
      ]
end

def send_welcome_message
    messages = [
      {
        type: 'text',
        content: "Bonjour je suis Mama et je vais t'aider à trouver très facilement quoi manger avec des suggestions aux petits oignons 🍲🥑🍅🍳💚!"
      },
      {
        type: 'quickReplies',
        content:
        {
          title: "Par quoi veux-tu commencer ?",
          buttons: [
            {
              title: 'Des suggestions ?',
              value: 'Donnes-moi des idées'
            },
            {
              title: 'Chercher une recette ?',
              value: 'activer la recherche'
            }
          ]
        }
      }
    ]
end
