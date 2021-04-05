#include <knifefight/chat.h>

#define MAX_CHAT_SIZE 192

stock CHAT_SayText2(int client, int author, const char[] message)
{
	Handle buffer = StartMessageOne("SayText2", client);
	if (buffer != INVALID_HANDLE)
	{
		if (GetUserMessageType() == UM_Protobuf)
		{
			PbSetBool(buffer, "chat", true);
			PbSetInt(buffer, "ent_idx", author);
			PbAddString(buffer, "params", message);
			PbAddString(buffer, "params", "");
			PbAddString(buffer, "params", "");
			PbAddString(buffer, "params", "");
			PbAddString(buffer, "params", "");
		}
		else
		{
			BfWriteByte(buffer, author);
			BfWriteByte(buffer, true);
			BfWriteString(buffer, message);
		}
		EndMessage();
	}
}

stock CHAT_SayText2ToAll(int author, const char[] message)
{
	Handle buffer = StartMessageAll("SayText2");
	if (buffer != INVALID_HANDLE)
	{
		if (GetUserMessageType() == UM_Protobuf)
		{
			PbSetBool(buffer, "chat", true);
			PbSetInt(buffer, "ent_idx", author);
			PbSetString(buffer, "msg_name", message);
			PbAddString(buffer, "params", "");
			PbAddString(buffer, "params", "");
			PbAddString(buffer, "params", "");
			PbAddString(buffer, "params", "");
		}
		else
		{
			BfWriteByte(buffer, author);
			BfWriteByte(buffer, true);
			BfWriteString(buffer, message);
		}
		EndMessage();
	}
}

stock CHAT_SayText(int client, int author, const char[] msg)
{
	if (!isColorMsg)
	{
		if (client)
		{
			PrintToChat(client, msg);
			return;
		}
		PrintToChatAll(msg);
		return;
	}
	char cmsg[192] = "\x1";
	StrCat(cmsg, sizeof(cmsg), msg);
	if (client)
	{
		CHAT_SayText2(client, author, cmsg);
		return;
	}
	CHAT_SayText2ToAll(author, cmsg);
	return;
}

stock CHAT_DetectColorMsg()
{
	isColorMsg = GetUserMessageId("SayText2") != INVALID_MESSAGE_ID;
}
