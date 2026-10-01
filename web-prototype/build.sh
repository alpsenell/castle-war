#!/bin/sh
# Wraps the page body (kale-savasi.html) into a standalone document (index.html).
cd "$(dirname "$0")"
{
  printf '%s\n' '<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover"><style>html{color-scheme:light}body{margin:0}[hidden]{display:none!important}</style></head><body>'
  cat kale-savasi.html
  printf '%s\n' '</body></html>'
} > index.html
