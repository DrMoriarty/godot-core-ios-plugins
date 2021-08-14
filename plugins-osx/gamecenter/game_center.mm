/*************************************************************************/
/*  game_center.mm                                                       */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2021 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2021 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "game_center.h"

#import "game_center_delegate.h"

#import <GameKit/GameKit.h>

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
typedef PackedInt32Array GodotIntArray;
typedef PackedFloat32Array GodotFloatArray;
#else
typedef PoolStringArray GodotStringArray;
typedef PoolIntArray GodotIntArray;
typedef PoolRealArray GodotFloatArray;
#endif

GameCenter *GameCenter::instance = NULL;
GodotGameCenterDelegate *gameCenterDelegate = nil;

void GameCenter::_register_methods() {
	register_method("authenticate", &GameCenter::authenticate);
	register_method("is_authenticated", &GameCenter::is_authenticated);

	register_method("post_score", &GameCenter::post_score);
	register_method("award_achievement", &GameCenter::award_achievement);
	register_method("reset_achievements", &GameCenter::reset_achievements);
	register_method("request_achievements", &GameCenter::request_achievements);
	register_method("request_achievement_descriptions", &GameCenter::request_achievement_descriptions);
	register_method("show_game_center", &GameCenter::show_game_center);
	register_method("request_identity_verification_signature", &GameCenter::request_identity_verification_signature);

	register_method("get_pending_event_count", &GameCenter::get_pending_event_count);
	register_method("pop_pending_event", &GameCenter::pop_pending_event);
};

void GameCenter::_init() {
}

godot_error GameCenter::authenticate() {
	//if this class isn't available, game center isn't implemented
	if ((NSClassFromString(@"GKLocalPlayer")) == nil) {
		return GODOT_ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(authenticateHandler)], GODOT_ERR_UNAVAILABLE);

	//GKDialogController *dialog = [[GKDialogController alloc] init];
	//ERR_FAIL_COND_V(!dialog, GODOT_FAILED);

	player.authenticateHandler = ^(NSViewController *controller, NSError *error) {
        printf("Auth handler called!\n");
    };

	// This handler is called several times.  First when the view needs to be shown, then again
	// after the view is cancelled or the user logs in.	 Or if the user's already logged in, it's
	// called just once to confirm they're authenticated.  This is why no result needs to be specified
	// in the presentViewController phase. In this case, more calls to this function will follow.
    /*
	player.authenticateHandler = ^(NSViewController *controller, NSError *error) {

		if (controller) {
            WARN_PRINT("Start GC authentification");
			Dictionary ret;
			ret["type"] = "authentication_start";
			pending_events.push_back(ret);
			//[dialog presentViewController:controller];
		} else {
            WARN_PRINT("Finish GC authentification");
			Dictionary ret;
			ret["type"] = "authentication";
			if (player.isAuthenticated) {
				ret["result"] = "ok";

				ret["player_id"] = [player.teamPlayerID UTF8String];

				GameCenter::get_singleton()->authenticated = true;
			} else {
				ret["result"] = "error";
				ret["error_code"] = (int64_t)error.code;
				ret["error_description"] = [error.localizedDescription UTF8String];
				GameCenter::get_singleton()->authenticated = false;
			};

			pending_events.push_back(ret);
		};
	};
    */
    godot::Godot::print("GC AUTH");

	return GODOT_OK;
};

bool GameCenter::is_authenticated() {
	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
    return player.isAuthenticated;
	//return authenticated;
};

godot_error GameCenter::post_score(Dictionary p_score) {
	ERR_FAIL_COND_V(!p_score.has("score") || !p_score.has("category"), GODOT_ERR_INVALID_PARAMETER);
	float score = p_score["score"];
	String category = p_score["category"];

	NSString *cat_str = [[NSString alloc] initWithUTF8String:category.utf8().get_data()];
	GKScore *reporter = [[GKScore alloc] initWithLeaderboardIdentifier:cat_str];
	reporter.value = score;

	ERR_FAIL_COND_V([GKScore respondsToSelector:@selector(reportScores)], GODOT_ERR_UNAVAILABLE);

	[GKScore reportScores:@[ reporter ]
			withCompletionHandler:^(NSError *error) {
				Dictionary ret;
				ret["type"] = "post_score";
				if (error == nil) {
					ret["result"] = "ok";
				} else {
					ret["result"] = "error";
					ret["error_code"] = (int64_t)error.code;
					ret["error_description"] = [error.localizedDescription UTF8String];
				};

				pending_events.push_back(ret);
			}];

	return GODOT_OK;
};

godot_error GameCenter::award_achievement(Dictionary p_params) {
	ERR_FAIL_COND_V(!p_params.has("name") || !p_params.has("progress"), GODOT_ERR_INVALID_PARAMETER);
	String name = p_params["name"];
	float progress = p_params["progress"];

	NSString *name_str = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
	GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:name_str];
	ERR_FAIL_COND_V(!achievement, GODOT_FAILED);

	ERR_FAIL_COND_V([GKAchievement respondsToSelector:@selector(reportAchievements)], GODOT_ERR_UNAVAILABLE);

	achievement.percentComplete = progress;
	achievement.showsCompletionBanner = NO;
	if (p_params.has("show_completion_banner")) {
		achievement.showsCompletionBanner = p_params["show_completion_banner"] ? YES : NO;
	}

	[GKAchievement reportAchievements:@[ achievement ]
				withCompletionHandler:^(NSError *error) {
					Dictionary ret;
					ret["type"] = "award_achievement";
					if (error == nil) {
						ret["result"] = "ok";
					} else {
						ret["result"] = "error";
						ret["error_code"] = (int64_t)error.code;
					};

					pending_events.push_back(ret);
				}];

	return GODOT_OK;
};

void GameCenter::request_achievement_descriptions() {
	[GKAchievementDescription loadAchievementDescriptionsWithCompletionHandler:^(NSArray *descriptions, NSError *error) {
		Dictionary ret;
		ret["type"] = "achievement_descriptions";
		if (error == nil) {
			ret["result"] = "ok";
			GodotStringArray names;
			GodotStringArray titles;
			GodotStringArray unachieved_descriptions;
			GodotStringArray achieved_descriptions;
			GodotIntArray maximum_points;
			Array hidden;
			Array replayable;

			for (NSUInteger i = 0; i < [descriptions count]; i++) {

				GKAchievementDescription *description = [descriptions objectAtIndex:i];

				const char *str = [description.identifier UTF8String];
				names.push_back(String(str != NULL ? str : ""));

				str = [description.title UTF8String];
				titles.push_back(String(str != NULL ? str : ""));

				str = [description.unachievedDescription UTF8String];
				unachieved_descriptions.push_back(String(str != NULL ? str : ""));

				str = [description.achievedDescription UTF8String];
				achieved_descriptions.push_back(String(str != NULL ? str : ""));

				maximum_points.push_back(description.maximumPoints);

				hidden.push_back(description.hidden == YES);

				replayable.push_back(description.replayable == YES);
			}

			ret["names"] = names;
			ret["titles"] = titles;
			ret["unachieved_descriptions"] = unachieved_descriptions;
			ret["achieved_descriptions"] = achieved_descriptions;
			ret["maximum_points"] = maximum_points;
			ret["hidden"] = hidden;
			ret["replayable"] = replayable;

		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

void GameCenter::request_achievements() {
	[GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
		Dictionary ret;
		ret["type"] = "achievements";
		if (error == nil) {
			ret["result"] = "ok";
			GodotStringArray names;
			GodotFloatArray percentages;

			for (NSUInteger i = 0; i < [achievements count]; i++) {

				GKAchievement *achievement = [achievements objectAtIndex:i];
				const char *str = [achievement.identifier UTF8String];
				names.push_back(String(str != NULL ? str : ""));

				percentages.push_back(achievement.percentComplete);
			}

			ret["names"] = names;
			ret["progress"] = percentages;

		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

void GameCenter::reset_achievements() {
	[GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
		Dictionary ret;
		ret["type"] = "reset_achievements";
		if (error == nil) {
			ret["result"] = "ok";
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

godot_error GameCenter::show_game_center(Dictionary p_params) {
	ERR_FAIL_COND_V(!NSProtocolFromString(@"GKGameCenterControllerDelegate"), GODOT_FAILED);

	GKGameCenterViewControllerState view_state = GKGameCenterViewControllerStateDefault;
	if (p_params.has("view")) {
		String view_name = p_params["view"];
		if (view_name == "default") {
			view_state = GKGameCenterViewControllerStateDefault;
		} else if (view_name == "leaderboards") {
			view_state = GKGameCenterViewControllerStateLeaderboards;
		} else if (view_name == "achievements") {
			view_state = GKGameCenterViewControllerStateAchievements;
		} else if (view_name == "challenges") {
			view_state = GKGameCenterViewControllerStateChallenges;
		} else {
			return GODOT_ERR_INVALID_PARAMETER;
		}
	}

	GKGameCenterViewController *controller = [[GKGameCenterViewController alloc] init];
	ERR_FAIL_COND_V(!controller, GODOT_FAILED);

	GKDialogController *dialog = [GKDialogController sharedDialogController]; // [[GKDialogController alloc] init];
	ERR_FAIL_COND_V(!dialog, GODOT_FAILED);
	dialog.parentWindow = NSApplication.sharedApplication.mainWindow;

	controller.gameCenterDelegate = gameCenterDelegate;
	controller.viewState = view_state;
	if (view_state == GKGameCenterViewControllerStateLeaderboards) {
		controller.leaderboardIdentifier = nil;
		if (p_params.has("leaderboard_name")) {
			String name = p_params["leaderboard_name"];
			NSString *name_str = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
			controller.leaderboardIdentifier = name_str;
		}
	}

	[dialog presentViewController:controller];

	return GODOT_OK;
};

godot_error GameCenter::request_identity_verification_signature() {
	ERR_FAIL_COND_V(!is_authenticated(), GODOT_ERR_UNAUTHORIZED);

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	void (^verificationSignatureHandler)(NSURL *publicKeyUrl, NSData *signature, NSData *salt, uint64_t timestamp, NSError *error) = ^(NSURL *publicKeyUrl, NSData *signature, NSData *salt, uint64_t timestamp, NSError *error) {
		Dictionary ret;
		ret["type"] = "identity_verification_signature";
		if (error == nil) {
			ret["result"] = "ok";
			ret["public_key_url"] = [publicKeyUrl.absoluteString UTF8String];
			ret["signature"] = [[signature base64EncodedStringWithOptions:0] UTF8String];
			ret["salt"] = [[salt base64EncodedStringWithOptions:0] UTF8String];
			ret["timestamp"] = timestamp;
			ret["player_id"] = [player.teamPlayerID UTF8String];
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
		};

		pending_events.push_back(ret);
	};

	if (@available(macOS 10.15.5, *)) {
		[player fetchItemsForIdentityVerificationSignature:verificationSignatureHandler];
	} else {
		[player generateIdentityVerificationSignatureWithCompletionHandler:verificationSignatureHandler];
	}

	return GODOT_OK;
};

void GameCenter::game_center_closed() {
	Dictionary ret;
	ret["type"] = "show_game_center";
	ret["result"] = "ok";
	pending_events.push_back(ret);
}

int GameCenter::get_pending_event_count() {
	return pending_events.size();
};

Variant GameCenter::pop_pending_event() {
	Variant front = pending_events.front();
	pending_events.pop_front();

	return front;
};

GameCenter *GameCenter::get_singleton() {
	return instance;
};

GameCenter::GameCenter() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	authenticated = false;

	gameCenterDelegate = [[GodotGameCenterDelegate alloc] init];
};

GameCenter::~GameCenter() {
	if (gameCenterDelegate) {
		gameCenterDelegate = nil;
	}
}
