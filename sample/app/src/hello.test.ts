import { describe, it, expect } from "vitest";
import { hello } from "./hello";

describe("hello", () => {
  it("TEST-1-1-1.1 [[HELLO-1]] hello returns Hello Claude!", () => {
    expect(hello()).toBe("Hello Claude!");
  });
});
