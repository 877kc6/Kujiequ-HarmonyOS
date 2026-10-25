import { EditorText, EditorParagraph } from '../models/Models';

export interface GameBoard { id: number; label: string; publish: boolean; }
// IDs and names from the official game's independent forum enums.
export function gameBoards(gameId: number): GameBoard[] {
  if (gameId === 2) {
    return [{ id: 2, label: '推荐', publish: false }, { id: 3, label: '伊甸闲庭', publish: true },
      { id: 4, label: '攻略', publish: true }, { id: 5, label: '同人图', publish: true }, { id: 16, label: '同人文', publish: true }];
  }
  if (gameId === 3) {
    return [{ id: 9, label: '推荐', publish: false }, { id: 10, label: '今州茶馆', publish: true },
      { id: 12, label: '攻略', publish: true }, { id: 15, label: '新手', publish: true }, { id: 11, label: '同人', publish: true }, { id: 17, label: 'Cosplay', publish: true }];
  }
  throw new Error('游戏编号无效');
}
export function publishBoard(gameId: number, boardId: number): boolean {
  return gameBoards(gameId).some((board: GameBoard): boolean => board.id === boardId && board.publish);
}
export function postContent(text: string): string {
  const textNode: EditorText = { type: 1, content: text, target: '' };
  const paragraphs: EditorParagraph[] = [{ contentType: 1, content: text, children: [textNode] }];
  return JSON.stringify(paragraphs);
}
export function escapedHtml(text: string): string {
  return '<p>' + text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/\n/g, '<br>') + '</p>';
}
