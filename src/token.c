#include <stdio.h>
#include <string.h>

#include "common.h"
#include "token.h"

Token *Token_new(void)
{
  Token *self = malloc(sizeof(Token));
  self->value = (char *)malloc(sizeof(char) * MAX_TOKEN_LENGTH + 1);
  memset(self->value, '\0', MAX_TOKEN_LENGTH + 1);
  self->type = ON_NONE;
  self->prev = NULL;
  self->next = NULL;
  return self;
}

void Token_free(Token* self)
{
  free(self->value);
  free(self);
}

bool Token_exists(Token* const self)
{
  if (strlen(self->value) > 0)
    return true;
  return false;
}
