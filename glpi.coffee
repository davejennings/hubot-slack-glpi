# Description:
#   Listens for GLPI ticket references, queries the GLPI API and retrieves details to post back to the Slack channel.
#
# Dependencies:
#    "hubot-env": "0.0.2",
#    "hubot-slack": ">=4.4.0",
#
# Configuration:
#   HUBOT_GLPI_HOST
#   HUBOT_GLPI_USER_TOKEN
#
# Commands:
#   <GLPI ticket URL> - Looks up and responds with information regarding the specified GLPI ticket
#
# Author:
#   Dave Jennings (@davejennings)

module.exports = (robot) ->

  https = require 'https'
  dateFormat = require 'dateformat'
  glpi_host = process.env.HUBOT_GLPI_HOST
  user_token = process.env.HUBOT_GLPI_USER_TOKEN
  robot.hear /front\/ticket\.form.php\?id=(\d+)/i, (msg) ->
    # base64 encoded string of - username:password e.g. johnsmith:password123
    # 'Authorization': 'Basic abcdefghijklmnopqrstuvwxyz12'
    #
    # Or API token from user preferences - but bug with GLPI means you can't login with your regular credentials 
    # after you use this token once without resetting your account
    # 'Authorization': 'user_token qQk2aMg2fVGAlxieC0vYRHbLOYobMHmYBQ1caMPS'
    headersObj =
      'Content-Type': 'application/json'
      'Authorization': 'user_token ' + user_token

    options =
      host: glpi_host
      port: 443
      path: '/apirest.php/initSession/'
      headers: headersObj

    https.get options, (res) ->
      data = ""
      res.on 'data', (chunk) ->
        data += chunk.toString()
      res.on 'end', () ->
        sessionDetails = JSON.parse(data)
        headersObj =
          'Content-Type': 'application/json'
          'Session-Token': sessionDetails.session_token

        options =
          host: glpi_host
          port: 443
          path: "/apirest.php/Ticket/#{msg.match[1]}"
          headers: headersObj

        https.get options, (res) ->
          data = ""
          res.on 'data', (chunk) ->
            data += chunk.toString()
          res.on 'end', () ->
            ticketDetails = JSON.parse(data)

            options =
              host: glpi_host
              port: 443
              path: "/apirest.php/Ticket/" + ticketDetails.id + "/Ticket_User"
              headers: headersObj
        
            https.get options, (res) ->
              data = ""
              res.on 'data', (chunk) ->
                data += chunk.toString()
              res.on 'end', () ->
                userDetails = JSON.parse(data)
                reporter = ""
                assignee = ""
                for user of userDetails
                  if userDetails[user].type == 1
                    reporterID = userDetails[user].users_id
                  if userDetails[user].type == 2
                    assigneeID = userDetails[user].users_id

                options =
                  host: glpi_host
                  port: 443
                  path: "/apirest.php/User/" + reporterID
                  headers: headersObj

                https.get options, (res) ->
                  data = ""
                  res.on 'data', (chunk) ->
                    data += chunk.toString()
                  res.on 'end', () ->
                    reporterDetails = JSON.parse(data)

                    options =
                      host: glpi_host
                      port: 443
                      path: "/apirest.php/User/" + assigneeID
                      headers: headersObj

                    https.get options, (res) ->
                      data = ""
                      res.on 'data', (chunk) ->
                        data += chunk.toString()
                      res.on 'end', () ->
                        assigneeDetails = JSON.parse(data)

                        options =
                          host: glpi_host
                          port: 443
                          path: "/apirest.php/killSession/"
                          headers: headersObj

                        https.get options, (res) ->
                          dateReported = new Date(ticketDetails.date)
                          dueDate = new Date(ticketDetails.time_to_resolve)
                          attachment = 
                            attachments:[
                              title: ticketDetails.name
                              fallback: ticketDetails.name
                              title_link: 'https://' + glpi_host + '/front/ticket.form.php?id=' + ticketDetails.id
                              text: ticketDetails.content
                              fields:[
                                { title: "Reported By", value: reporterDetails.firstname + " " + reporterDetails.realname, short: "true" }
                                { title: "Date Reported", value: dateFormat(dateReported, "dd/mm/yyyy HH:MM"), short: "true" }
                                { title: "Assigned To", value: assigneeDetails.firstname + " " + assigneeDetails.realname, short: "true" }
                                { title: "Due Date", value: dateFormat(dueDate, "dd/mm/yyyy HH:MM"), short: "true" }
                              ]
                            ]

                          robot.send room: msg.envelope.room, attachment
