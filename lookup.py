import json
import os
from requests_oauthlib import OAuth1Session
import sys
import time

# In your terminal please set your environment variables by running the following lines of code.
# export 'CONSUMER_KEY'='<your_consumer_key>'
# export 'CONSUMER_SECRET'='<your_consumer_secret>'

class TwitterStats():

    __request_token_url = "https://api.twitter.com/oauth/request_token"

    @classmethod
    def split_list(cls, list, sub_size):
        for i in range(0, len(list), sub_size):
            yield list[i : i + sub_size]

    @classmethod
    def __make_single_twitter_params(cls, users):
        return {'usernames': ','.join(users), 'user.fields': 'public_metrics'}

    @classmethod
    def make_twitter_params(cls, users, max_users_per_request):
        params = []
        for grouped in cls.split_list(users, max_users_per_request):
            params.append(cls.__make_single_twitter_params(grouped))
        return params

    @classmethod
    def __parse_user_data(cls, user_data):
        username = user_data['username']
        tweet_count = user_data['public_metrics']['tweet_count']
        return (username, tweet_count)

    def __init__(self, consumer_key, consumer_secret, users):
        self.consumer_key = consumer_key
        self.consumer_secret = consumer_secret
        self.users = users

    def __make_auth(self):
        # Get request token
        
        oauth = OAuth1Session(self.consumer_key, client_secret=self.consumer_secret)

        try:
            fetch_response = oauth.fetch_request_token(self.__request_token_url)
        except ValueError:
            print(
                "There may have been an issue with the consumer_key or consumer_secret you entered."
            )

        resource_owner_key = fetch_response.get("oauth_token")
        resource_owner_secret = fetch_response.get("oauth_token_secret")
        print("Got OAuth token: %s" % resource_owner_key)

        # # Get authorization
        base_authorization_url = "https://api.twitter.com/oauth/authorize"
        authorization_url = oauth.authorization_url(base_authorization_url)
        print("Please go here and authorize: %s" % authorization_url)
        verifier = input("Paste the PIN here: ")

        # Get the access token
        access_token_url = "https://api.twitter.com/oauth/access_token"
        oauth = OAuth1Session(
            self.consumer_key,
            client_secret=self.consumer_secret,
            resource_owner_key=resource_owner_key,
            resource_owner_secret=resource_owner_secret,
            verifier=verifier,
        )
        oauth_tokens = oauth.fetch_access_token(access_token_url)

        access_token = oauth_tokens["oauth_token"]
        access_token_secret = oauth_tokens["oauth_token_secret"]

        # Make the request
        return OAuth1Session(
            self.consumer_key,
            client_secret=self.consumer_secret,
            resource_owner_key=access_token,
            resource_owner_secret=access_token_secret,
        )

    def fetch_stats(self):
        oauth = self.__make_auth()
        user_tweets = {}
        for params in self.make_twitter_params(self.users, 100):
            response = oauth.get(
                "https://api.twitter.com/2/users/by", params=params
            )

            if response.status_code != 200:
                raise Exception(
                    "Request returned an error: {} {}".format(response.status_code, response.text)
                )

            json_response = response.json()

            for user_data in json_response['data']:
                tweet_info = self.__parse_user_data(user_data)
                user_tweets[tweet_info[0]] = tweet_info[1]

            time.sleep(3)
        return user_tweets