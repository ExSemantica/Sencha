# Sencha

## Hierarchy

- `lib/sencha/commands` - IRC command handling
- `lib/sencha/handler` - socket handling
- `lib/sencha/user` - user handling after handing off from authentication
- `lib/sencha/message` - encode and decode IRC messages

## Rehashable files

### MOTD

The `data/motd.txt` file can be used to give a LF-terminated MOTD.

### K-lines

The `data/klines.txt` file is an Erlang terms list, which allows you to K-Line
by Erlang `:file.consult` term files.

Make sure the terms are binaries. You specify a CIDR range as the first tuple
term and the reason for your K-Line as the second tuple term.

```
{<<"127.0.0.0/8">>, <<"Test K-Lining localhost">>}.
```

TODO: Allow Reverse DNS hostmask K-lines/channel modes too.