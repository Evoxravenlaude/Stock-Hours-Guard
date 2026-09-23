import { test } from "node:test";
import assert from "node:assert/strict";
import { Session, sessionAt } from "./session.js";

const et = (s: string) => new Date(s); // ISO strings with explicit -04:00 (EDT) offset below

test("regular hours", () => assert.equal(sessionAt(et("2026-09-22T10:00:00-04:00")), Session.Regular));
test("pre-market", () => assert.equal(sessionAt(et("2026-09-22T08:00:00-04:00")), Session.PreMarket));
test("post-market", () => assert.equal(sessionAt(et("2026-09-22T17:30:00-04:00")), Session.PostMarket));
test("overnight weekday", () => assert.equal(sessionAt(et("2026-09-23T02:00:00-04:00")), Session.Overnight));
test("saturday closed", () => assert.equal(sessionAt(et("2026-09-26T12:00:00-04:00")), Session.Closed));
test("sunday before 8pm closed", () => assert.equal(sessionAt(et("2026-09-27T18:00:00-04:00")), Session.Closed));
test("sunday 8pm overnight opens", () => assert.equal(sessionAt(et("2026-09-27T20:30:00-04:00")), Session.Overnight));
test("friday after 8pm closed", () => assert.equal(sessionAt(et("2026-09-25T21:00:00-04:00")), Session.Closed));
test("thanksgiving closed midday", () => assert.equal(sessionAt(et("2026-11-26T11:00:00-05:00")), Session.Closed));
test("early close day post-market at 2pm", () => assert.equal(sessionAt(et("2026-11-27T14:00:00-05:00")), Session.PostMarket));
