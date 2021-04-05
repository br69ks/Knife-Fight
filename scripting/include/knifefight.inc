#if defined _knifefight_included
 #endinput
#endif
#define _knifefight_included

/**
 *  Called when a player declines a fight
 *	@param client  Player who declined
 */
 forward void OnPlayerDeclineFight(int client);
 
 /**
 *  Called when a player accepts a fight
 *	@param client  Player who accepted
 */
 forward void OnPlayerAcceptFight(int client);
 
/**
 *  Called when the Knife Fight starts
 *  @param player1
 * 	@param player2
 */
 forward void OnKnifeFightStart(int player1, int player2);
 
 /**
 *  Called when the Knife Fight ends
 * @param winner  Player who won the fight
 */
 forward void OnKnifeFightEnd(int winner);