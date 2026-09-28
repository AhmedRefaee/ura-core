import { describe, it, expect } from 'vitest';
import { getStatusSteps, getCurrentStepIndex } from './statusSteps';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: null, direction: 'outbound', entityId: 'e1', entity: null,
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: null, assignedAt: null, pickedUpAt: null,
    moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

describe('getStatusSteps', () => {
  it('returns the two-step sequence for an inbound_external order', () => {
    const steps = getStatusSteps(order({ direction: 'inbound_external' }));
    expect(steps.map((s) => s.status)).toEqual(['assigned', 'delivered_to_storage']);
  });

  it('returns the four-step sequence for an inbound_rep order', () => {
    const steps = getStatusSteps(order({ direction: 'inbound_rep' }));
    expect(steps.map((s) => s.status)).toEqual(['assigned', 'picked_up', 'on_the_move', 'delivered_to_storage']);
  });

  it('returns the four-step outbound sequence ending in delivered', () => {
    const steps = getStatusSteps(order({ direction: 'outbound' }));
    expect(steps.map((s) => s.status)).toEqual(['assigned', 'picked_up', 'on_the_move', 'delivered']);
  });

  it('uses "أُرسل من المخزن" for picked_up when outbound order involves storage items', () => {
    const o = order({
      direction: 'outbound',
      items: [{
        id: 'i1', orderId: 'o1', inventoryId: 'inv1', inventoryName: 'أكياس أرز', quantity: 5,
        finalQuantity: null, isCustom: false, customDescription: null, checkStatus: 'pending',
        checkedBy: null, checkedAt: null, checker: null, wasUnavailableAtCreation: false,
      }],
    });
    const steps = getStatusSteps(o);
    expect(steps[1].label).toBe('أُرسل من المخزن');
  });

  it('uses "تم الاستلام" for picked_up when outbound order has no storage items', () => {
    const o = order({
      direction: 'outbound',
      items: [{
        id: 'i1', orderId: 'o1', inventoryId: null, inventoryName: null, quantity: 5,
        finalQuantity: null, isCustom: true, customDescription: 'صنف مخصص', checkStatus: 'pending',
        checkedBy: null, checkedAt: null, checker: null, wasUnavailableAtCreation: false,
      }],
    });
    const steps = getStatusSteps(o);
    expect(steps[1].label).toBe('تم الاستلام');
  });
});

describe('getCurrentStepIndex', () => {
  it('finds the index matching the order\'s current status', () => {
    const o = order({ direction: 'outbound', status: 'on_the_move' });
    const steps = getStatusSteps(o);
    expect(getCurrentStepIndex(steps, o)).toBe(2);
  });

  it('defaults to the first step when nothing matches', () => {
    const o = order({ direction: 'outbound', status: 'assigned' });
    const steps = getStatusSteps(o);
    expect(getCurrentStepIndex(steps, o)).toBe(0);
  });
});
